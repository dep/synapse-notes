import git from 'isomorphic-git';
import * as FileSystem from 'expo-file-system/legacy';
import AsyncStorage from '@react-native-async-storage/async-storage';

const getDocumentDirectory = () => FileSystem.documentDirectory || 'file:///';

const toExpoUri = (inputPath: string): string => {
  if (!inputPath) {
    return inputPath;
  }

  if (inputPath.startsWith('file:///')) {
    return inputPath;
  }

  if (inputPath.startsWith('file://')) {
    return `file:///${inputPath.slice('file://'.length).replace(/^\/+/, '')}`;
  }

  if (inputPath.startsWith('file:/')) {
    return `file:///${inputPath.slice('file:/'.length).replace(/^\/+/, '')}`;
  }

  if (inputPath.startsWith('/')) {
    return `file://${inputPath}`;
  }

  const docDir = getDocumentDirectory().replace(/\/+$/, '');
  return `${docDir}/${inputPath.replace(/^\/+/, '')}`;
};

const createFsError = (code: string, syscall: string, targetPath: string) => {
  const error = new Error(`${code}: no such file or directory, ${syscall} '${targetPath}'`) as Error & {
    code: string;
    errno: number;
    syscall: string;
    path: string;
  };

  error.code = code;
  error.errno = -2;
  error.syscall = syscall;
  error.path = targetPath;

  return error;
};

const getParentPath = (targetPath: string) => {
  const normalizedPath = targetPath.replace(/\/+$/, '');
  const lastSlashIndex = normalizedPath.lastIndexOf('/');

  if (lastSlashIndex <= 'file:///'.length - 1) {
    return null;
  }

  return normalizedPath.slice(0, lastSlashIndex);
};

const ensureParentDirectory = async (targetPath: string) => {
  const parentPath = getParentPath(targetPath);

  if (!parentPath) {
    return;
  }

  await FileSystem.makeDirectoryAsync(toExpoUri(parentPath), {
    intermediates: true,
  });
};

// Base64 helpers for lossless binary round-tripping through expo-file-system.
// expo-file-system only supports UTF-8 and Base64 — binary data must go through
// Base64 to avoid corruption when writing pack files and other git objects.
const uint8ToBase64 = (bytes: Uint8Array): string => {
  // Use a reduce-based approach to avoid spread call stack limits on large arrays
  const CHUNK = 4096;
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i += CHUNK) {
    const slice = bytes.subarray(i, Math.min(i + CHUNK, bytes.byteLength));
    for (let j = 0; j < slice.length; j++) {
      binary += String.fromCharCode(slice[j]);
    }
  }
  return btoa(binary);
};

const base64ToUint8 = (b64: string): Uint8Array => {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
};

// Collect an async iterable body into a single Uint8Array
const collectBody = async (
  body?: Iterable<Uint8Array> | AsyncIterable<Uint8Array>
): Promise<Uint8Array> => {
  if (!body) return new Uint8Array(0);
  const chunks: Uint8Array[] = [];
  for await (const chunk of body as AsyncIterable<Uint8Array>) {
    chunks.push(chunk);
  }
  const totalLength = chunks.reduce((n, c) => n + c.byteLength, 0);
  const merged = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return merged;
};

const toFetchBody = (bytes: Uint8Array, method: string): string | ArrayBuffer | undefined => {
  if (bytes.byteLength === 0) {
    return undefined;
  }

  // isomorphic-git's upload-pack request body is pkt-line text. React Native's
  // fetch is more reliable with string bodies than raw Uint8Array bodies on Android.
  if (method === 'POST') {
    return new TextDecoder().decode(bytes);
  }

  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
};

type XhrBlobResponse = {
  status: number;
  statusText: string;
  headers: Record<string, string>;
  responseURL: string;
  blob: Blob;
};

const xhrBlobRequest = (
  url: string,
  method: string,
  headers: Record<string, string>,
  body?: string | ArrayBuffer
): Promise<XhrBlobResponse> => {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open(method, url, true);
    xhr.responseType = 'blob';

    Object.entries(headers).forEach(([key, value]) => {
      xhr.setRequestHeader(key, value);
    });

    xhr.onload = () => {
      const rawHeaders = xhr.getAllResponseHeaders();
      const parsedHeaders: Record<string, string> = {};
      rawHeaders.trim().split(/[\r\n]+/).forEach((line) => {
        if (!line) return;
        const idx = line.indexOf(':');
        if (idx === -1) return;
        parsedHeaders[line.slice(0, idx).trim().toLowerCase()] = line.slice(idx + 1).trim();
      });

      resolve({
        status: xhr.status,
        statusText: xhr.statusText,
        headers: parsedHeaders,
        responseURL: xhr.responseURL || url,
        blob: xhr.response,
      });
    };

    xhr.onerror = () => reject(new Error('XHR network error'));
    xhr.ontimeout = () => reject(new Error('XHR timeout'));
    xhr.onabort = () => reject(new Error('XHR aborted'));

    if (body === undefined) {
      xhr.send();
    } else {
      xhr.send(body as any);
    }
  });
};


const http = {
  async request({
    url,
    method = 'GET',
    headers = {},
    body,
  }: {
    url: string;
    method?: string;
    headers?: Record<string, string>;
    body?: Iterable<Uint8Array> | AsyncIterable<Uint8Array>;
  }) {
    // Materialise request body before sending (streaming POST not supported in RN fetch)
    const requestBytes = await collectBody(body);
    const requestBody = toFetchBody(requestBytes, method);

    // For the large pack-data POST, stream directly to a temp file via
    // FileSystem.downloadAsync to avoid buffering 100s of MB in JS heap.
    // We detect this by method=POST and the upload-pack service URL.
    const isPackRequest = method === 'POST' && url.includes('git-upload-pack');

    if (isPackRequest) {
      console.log('[git-http] POST (pack) via xhr:', url, 'request bytes:', requestBytes.byteLength, 'body type:', typeof requestBody);

      const docDir = (FileSystem.documentDirectory || 'file:///').replace(/\/+$/, '');
      const tempDir = `${docDir}/.git-tmp`;
      await FileSystem.makeDirectoryAsync(tempDir, { intermediates: true }).catch(() => {});
      const tempOut = `${tempDir}/pack-${Date.now()}.bin`;

      try {
        console.log('[git-http] POST starting xhr');
        const response = await xhrBlobRequest(url, method, headers, requestBody);
        console.log('[git-http] POST xhr returned');

        console.log('[git-http] POST ->', response.status, 'ct:', response.headers['content-type']);

        if ((response.status < 200 || response.status >= 300) && response.status !== 401) {
          const text = await response.blob.text();
          const bytes = new TextEncoder().encode(text);
          return {
            url: response.responseURL || url,
            method,
            statusCode: response.status,
            statusMessage: response.statusText,
            headers: response.headers,
            body: singleChunkIterable(bytes),
          };
        }

        // Strategy: try blob→FileReader (avoids one ArrayBuffer copy), fall back
        // to arrayBuffer if FileReader is unavailable on this Hermes version.
        let b64Pack: string;

        try {
          console.log('[git-http] trying blob path...');
          const blob = response.blob;
          console.log('[git-http] blob size:', blob.size);
          b64Pack = await new Promise<string>((resolve, reject) => {
            const fr = new FileReader();
            fr.onload = () => {
              const result = fr.result as string;
              const idx = result.indexOf(',');
              resolve(idx >= 0 ? result.slice(idx + 1) : result);
            };
            fr.onerror = () => reject(fr.error);
            fr.readAsDataURL(blob);
          });
          console.log('[git-http] blob→base64 done, b64 length:', b64Pack.length);
        } catch (blobErr) {
          console.log('[git-http] blob path failed, falling back to arrayBuffer:', (blobErr as Error).message);
          const arrayBuf = await response.blob.arrayBuffer();
          const bytes = new Uint8Array(arrayBuf);
          console.log('[git-http] arrayBuffer bytes:', bytes.byteLength);
          b64Pack = uint8ToBase64(bytes);
        }

        // Write pack to temp file on device storage
        await FileSystem.writeAsStringAsync(tempOut, b64Pack, {
          encoding: FileSystem.EncodingType.Base64,
        });
        const fileInfo = await FileSystem.getInfoAsync(tempOut);
        const totalSize = fileInfo.size || 0;
        console.log('[git-http] pack on disk, bytes:', totalSize);

        // Hand isomorphic-git the bytes read back from disk in one shot.
        // expo-file-system has no range reads so we read the whole file once —
        // the base64 string lives in JS heap briefly then gets GC'd.
        let served = false;
        const iterable = {
          [Symbol.asyncIterator]() { return this; },
          async next(): Promise<{ done: boolean; value: Uint8Array | undefined }> {
            if (served) {
              await FileSystem.deleteAsync(tempOut, { idempotent: true }).catch(() => {});
              return { done: true, value: undefined };
            }
            served = true;
            const allB64 = await FileSystem.readAsStringAsync(tempOut, {
              encoding: FileSystem.EncodingType.Base64,
            });
            return { done: false, value: base64ToUint8(allB64) };
          },
          async return() {
            await FileSystem.deleteAsync(tempOut, { idempotent: true }).catch(() => {});
            return { done: true as const, value: undefined };
          },
        };

        return {
          url: response.responseURL || url,
          method,
          statusCode: response.status,
          statusMessage: response.statusText,
          headers: response.headers,
          body: iterable,
        };

      } catch (err) {
        await FileSystem.deleteAsync(tempOut, { idempotent: true }).catch(() => {});
        throw err;
      }
    }

    // Non-pack requests (info/refs, etc.) are small — buffer normally
    const response = await fetch(url, { method, headers, body: requestBody });

    const responseHeaders: Record<string, string> = {};
    response.headers.forEach((v: string, k: string) => {
      responseHeaders[k] = v;
    });

    console.log('[git-http]', method, url, '->', response.status,
      'ct:', responseHeaders['content-type']);

    const arrayBuf = await response.arrayBuffer();
    const bodyBytes = new Uint8Array(arrayBuf);
    console.log('[git-http] buffered bytes:', bodyBytes.byteLength);

    return {
      url: response.url || url,
      method,
      statusCode: response.status,
      statusMessage: response.statusText,
      headers: responseHeaders,
      body: singleChunkIterable(bodyBytes),
    };
  },
};

function singleChunkIterable(bytes: Uint8Array) {
  let done = false;
  return {
    [Symbol.asyncIterator]() { return this; },
    async next(): Promise<{ done: boolean; value: Uint8Array | undefined }> {
      if (done) return { done: true, value: undefined };
      done = true;
      return { done: false, value: bytes };
    },
    async return() {
      done = true;
      return { done: true as const, value: undefined };
    },
  };
}

// Node.js fs-compatible adapter for expo-file-system
// This allows isomorphic-git to work with Expo's FileSystem API
const fs = {
  promises: {
    async readFile(filepath: string, options?: { encoding?: string }): Promise<string | Uint8Array> {
      // Read as Base64 to preserve binary content (pack files, git objects, etc.)
      const b64 = await FileSystem.readAsStringAsync(toExpoUri(filepath), {
        encoding: FileSystem.EncodingType.Base64,
      });
      const bytes = base64ToUint8(b64);
      if (options?.encoding === 'utf8') {
        return new TextDecoder().decode(bytes);
      }
      return bytes;
    },

    async writeFile(filepath: string, data: string | Uint8Array, options?: { encoding?: string }): Promise<void> {
      // Always write as Base64 to preserve binary content (pack files, git objects, etc.)
      let bytes: Uint8Array;
      if (data instanceof Uint8Array) {
        bytes = data;
      } else {
        bytes = new TextEncoder().encode(data);
      }
      await ensureParentDirectory(filepath);
      await FileSystem.writeAsStringAsync(toExpoUri(filepath), uint8ToBase64(bytes), {
        encoding: FileSystem.EncodingType.Base64,
      });
    },

    async mkdir(dirpath: string, options?: { recursive?: boolean }): Promise<void> {
      await FileSystem.makeDirectoryAsync(toExpoUri(dirpath), {
        intermediates: options?.recursive ?? false 
      });
    },

    async rmdir(dirpath: string): Promise<void> {
      await FileSystem.deleteAsync(toExpoUri(dirpath), { idempotent: true });
    },

    async readdir(dirpath: string): Promise<string[]> {
      return await FileSystem.readDirectoryAsync(toExpoUri(dirpath));
    },

    async unlink(filepath: string): Promise<void> {
      await FileSystem.deleteAsync(toExpoUri(filepath), { idempotent: true });
    },

    async rename(oldpath: string, newpath: string): Promise<void> {
      // Expo doesn't have a direct rename, so we copy and delete
      await ensureParentDirectory(newpath);
      await FileSystem.copyAsync({ from: toExpoUri(oldpath), to: toExpoUri(newpath) });
      await FileSystem.deleteAsync(toExpoUri(oldpath), { idempotent: true });
    },

    async stat(filepath: string): Promise<{
      type: string;
      mode: number;
      size: number;
      ino: number;
      mtimeMs: number;
      ctimeMs: number;
      uid: number;
      gid: number;
      dev: number;
      isFile: () => boolean;
      isDirectory: () => boolean;
      isSymbolicLink: () => boolean;
    }> {
      const info = await FileSystem.getInfoAsync(toExpoUri(filepath));
      if (!info.exists) {
        throw createFsError('ENOENT', 'stat', filepath);
      }
      
      const size = info.size || 0;
      const mtimeMs = info.modificationTime ? info.modificationTime * 1000 : Date.now();
      
      return {
        type: info.isDirectory ? 'directory' : 'file',
        mode: 0o644,
        size,
        ino: 0,
        mtimeMs,
        ctimeMs: mtimeMs,
        uid: 0,
        gid: 0,
        dev: 0,
        isFile: () => !info.isDirectory,
        isDirectory: () => info.isDirectory,
        isSymbolicLink: () => false,
      };
    },

    async lstat(filepath: string): Promise<ReturnType<typeof fs.promises.stat>> {
      // Check if this path is a stored symlink first
      const symlinkPath = toExpoUri(filepath + '.symlink');
      const symlinkInfo = await FileSystem.getInfoAsync(symlinkPath);
      if (symlinkInfo.exists) {
        const mtimeMs = symlinkInfo.modificationTime ? symlinkInfo.modificationTime * 1000 : Date.now();
        return {
          type: 'symlink',
          mode: 0o120000,
          size: symlinkInfo.size || 0,
          ino: 0,
          mtimeMs,
          ctimeMs: mtimeMs,
          uid: 0,
          gid: 0,
          dev: 0,
          isFile: () => false,
          isDirectory: () => false,
          isSymbolicLink: () => true,
        };
      }
      return await fs.promises.stat(filepath);
    },

    async symlink(target: string, filepath: string): Promise<void> {
      // Store symlink target as a sidecar file (filepath.symlink)
      await ensureParentDirectory(filepath);
      await FileSystem.writeAsStringAsync(toExpoUri(filepath + '.symlink'), target, {
        encoding: FileSystem.EncodingType.UTF8,
      });
    },

    async readlink(filepath: string): Promise<string> {
      // Read symlink target from sidecar file
      const symlinkPath = toExpoUri(filepath + '.symlink');
      const info = await FileSystem.getInfoAsync(symlinkPath);
      if (!info.exists) {
        throw createFsError('ENOENT', 'readlink', filepath);
      }
      return await FileSystem.readAsStringAsync(symlinkPath, {
        encoding: FileSystem.EncodingType.UTF8,
      });
    },
  },
};

export enum GitErrorType {
  AUTH_FAILURE = 'AUTH_FAILURE',
  NETWORK_ERROR = 'NETWORK_ERROR',
  CONFLICT = 'CONFLICT',
  NOT_A_REPOSITORY = 'NOT_A_REPOSITORY',
  UNKNOWN = 'UNKNOWN',
}

export class GitError extends Error {
  type: GitErrorType;
  originalError?: Error;

  constructor(message: string, type: GitErrorType, originalError?: Error) {
    super(message);
    this.name = 'GitError';
    this.type = type;
    this.originalError = originalError;
  }
}

interface GitCredentials {
  username: string;
  token: string;
}

interface CredentialsMap {
  [repoUrl: string]: GitCredentials;
}

interface StatusResult {
  modified: string[];
  deleted: string[];
  added: string[];
  hasChanges: boolean;
}

interface SyncResult {
  pulled: boolean;
  committed: string | null;
  pushed: boolean;
}

interface ChangedEntry {
  path: string;
  sha: string;
  mode: string;
}

interface GitHubRepoRef {
  owner: string;
  repo: string;
  repoUrl: string;
}

interface RepoMetadataFile {
  version: number;
  transport: 'github-api';
  repoUrl: string;
  owner: string;
  repo: string;
  branch: string;
  commitSha: string;
  treeSha: string;
  files: Record<string, { sha: string; mode: string; type: string }>;
}

interface GitHubTreeEntry {
  path: string;
  type: string;
  mode: string;
  sha: string;
}

const CREDENTIALS_KEY = 'git_credentials';
const REPO_METADATA_DIR = '.synapse';
const REPO_METADATA_FILE = 'repo.json';

const joinRepoPath = (root: string, child: string) => {
  const normalizedRoot = root.replace(/\/+$/, '');
  const normalizedChild = child.replace(/^\/+/, '');
  return `${normalizedRoot}/${normalizedChild}`;
};

const getRepoMetadataPath = (dir: string) => joinRepoPath(joinRepoPath(dir, REPO_METADATA_DIR), REPO_METADATA_FILE);

const isGitHubUrl = (url: string) => /github\.com[:/]/i.test(url);

const parseGitHubRepo = (url: string): GitHubRepoRef | null => {
  const normalized = url.trim().replace(/\.git$/, '').replace(/\/+$/, '');
  const httpsMatch = normalized.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)$/i);
  if (httpsMatch) {
    const [, owner, repo] = httpsMatch;
    return { owner, repo, repoUrl: `https://github.com/${owner}/${repo}` };
  }

  const sshMatch = normalized.match(/^git@github\.com:([^/]+)\/([^/]+)$/i);
  if (sshMatch) {
    const [, owner, repo] = sshMatch;
    return { owner, repo, repoUrl: `https://github.com/${owner}/${repo}` };
  }

  return null;
};

const toGitHubApiHeaders = (token?: string) => ({
  Accept: 'application/vnd.github+json',
  ...(token ? { Authorization: `Bearer ${token}` } : {}),
});

const sanitizeGitHubBase64 = (content: string) => content.replace(/\n/g, '');

const listLocalRepositoryFiles = async (dir: string, baseDir = dir): Promise<string[]> => {
  const entries = await FileSystem.readDirectoryAsync(toExpoUri(dir));
  const files: string[] = [];

  for (const entry of entries) {
    if (entry === REPO_METADATA_DIR || entry === '.git' || entry.endsWith('.symlink')) {
      continue;
    }

    const fullPath = joinRepoPath(dir, entry);
    const info = await FileSystem.getInfoAsync(toExpoUri(fullPath));
    if (!info.exists) {
      continue;
    }

    if (info.isDirectory) {
      files.push(...await listLocalRepositoryFiles(fullPath, baseDir));
      continue;
    }

    const relativePath = fullPath.slice(baseDir.replace(/\/+$/, '').length + 1);
    files.push(relativePath);
  }

  return files.sort();
};

const getRelativeRepoPath = (dir: string, filePath: string) => {
  const normalizedDir = toExpoUri(dir).replace(/\/+$/, '');
  const normalizedFile = toExpoUri(filePath).replace(/\/+$/, '');
  if (!normalizedFile.startsWith(normalizedDir + '/')) {
    return normalizedFile;
  }
  return normalizedFile.slice(normalizedDir.length + 1);
};

function getGitErrorType(error: Error): GitErrorType {
  const message = error.message.toLowerCase();
  
  if (message.includes('401') || message.includes('unauthorized') || message.includes('auth')) {
    return GitErrorType.AUTH_FAILURE;
  }
  if (message.includes('network') || message.includes('fetch') || message.includes('connection')) {
    return GitErrorType.NETWORK_ERROR;
  }
  if (message.includes('conflict') || message.includes('merge')) {
    return GitErrorType.CONFLICT;
  }
  if (message.includes('not a git repository')) {
    return GitErrorType.NOT_A_REPOSITORY;
  }
  
  return GitErrorType.UNKNOWN;
}

export class GitService {
  private static instance: GitService | null = null;

  private constructor() {}

  static getInstance(): GitService {
    if (!GitService.instance) {
      GitService.instance = new GitService();
    }
    return GitService.instance;
  }

  static clearInstance(): void {
    GitService.instance = null;
  }

  private static async getAuthCallback(url: string): Promise<git.AuthCallback | undefined> {
    const credentials = await GitService.getCredentials(url);
    if (!credentials) {
      return undefined;
    }

    return () => ({
      username: credentials.username,
      password: credentials.token,
    });
  }

  private handleError(error: Error, operation: string): never {
    const errorType = getGitErrorType(error);
    const message = `${operation} failed: ${error.message}`;
    throw new GitError(message, errorType, error);
  }

  private async getGitHubToken(repoUrl: string): Promise<string | undefined> {
    const repoCredentials = await GitService.getCredentials(repoUrl);
    if (repoCredentials?.token) {
      return repoCredentials.token;
    }

    const defaultCredentials = await GitService.getCredentials('default');
    return defaultCredentials?.token;
  }

  private async githubRequest<T>(
    path: string,
    repoUrl: string,
    options?: RequestInit & { token?: string }
  ): Promise<T> {
    const method = options?.method || 'GET';
    const token = options?.token ?? await this.getGitHubToken(repoUrl);
    const separator = path.includes('?') ? '&' : '?';
    const requestPath = method === 'GET'
      ? `${path}${separator}cache_bust=${Date.now()}`
      : path;

    const response = await fetch(`https://api.github.com${requestPath}`, {
      method,
      headers: {
        ...toGitHubApiHeaders(token),
        ...(method === 'GET'
          ? {
              'Cache-Control': 'no-cache, no-store',
              Pragma: 'no-cache',
            }
          : {}),
        ...(options?.headers || {}),
      },
      body: options?.body,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`GitHub API ${response.status}: ${text || response.statusText}`);
    }

    return response.json() as Promise<T>;
  }

  private async loadRepoMetadata(dir: string): Promise<RepoMetadataFile | null> {
    const metadataPath = getRepoMetadataPath(dir);
    const info = await FileSystem.getInfoAsync(toExpoUri(metadataPath));
    if (!info.exists) {
      return null;
    }

    const raw = await FileSystem.readAsStringAsync(toExpoUri(metadataPath), {
      encoding: FileSystem.EncodingType.UTF8,
    });
    return JSON.parse(raw) as RepoMetadataFile;
  }

  private async saveRepoMetadata(dir: string, metadata: RepoMetadataFile): Promise<void> {
    const metadataDir = joinRepoPath(dir, REPO_METADATA_DIR);
    await FileSystem.makeDirectoryAsync(toExpoUri(metadataDir), { intermediates: true });
    await FileSystem.writeAsStringAsync(toExpoUri(getRepoMetadataPath(dir)), JSON.stringify(metadata), {
      encoding: FileSystem.EncodingType.UTF8,
    });
  }

  private async isGitHubApiRepository(dir: string): Promise<boolean> {
    const metadata = await this.loadRepoMetadata(dir);
    return metadata?.transport === 'github-api';
  }

  private async cloneViaGitHubApi(
    repoRef: GitHubRepoRef,
    dir: string,
    onProgress?: git.ProgressCallback
  ): Promise<void> {
    const repo = await this.githubRequest<{ default_branch: string }>(
      `/repos/${repoRef.owner}/${repoRef.repo}`,
      repoRef.repoUrl
    );
    const branch = repo.default_branch;

    const branchInfo = await this.githubRequest<{ commit: { sha: string } }>(
      `/repos/${repoRef.owner}/${repoRef.repo}/branches/${encodeURIComponent(branch)}`,
      repoRef.repoUrl
    );
    const commitSha = branchInfo.commit.sha;

    const commitInfo = await this.githubRequest<{ tree: { sha: string } }>(
      `/repos/${repoRef.owner}/${repoRef.repo}/git/commits/${commitSha}`,
      repoRef.repoUrl
    );
    const treeSha = commitInfo.tree.sha;

    const tree = await this.githubRequest<{ tree: Array<{ path: string; type: string; mode: string; sha: string }> }>(
      `/repos/${repoRef.owner}/${repoRef.repo}/git/trees/${treeSha}?recursive=1`,
      repoRef.repoUrl
    );

    const blobs = tree.tree.filter((entry) => entry.type === 'blob');
    const files: RepoMetadataFile['files'] = {};

    await FileSystem.makeDirectoryAsync(toExpoUri(dir), { intermediates: true });

    let loaded = 0;
    for (const blob of blobs) {
      const blobResponse = await this.githubRequest<{ content: string; encoding: string }>(
        `/repos/${repoRef.owner}/${repoRef.repo}/git/blobs/${blob.sha}`,
        repoRef.repoUrl
      );

      const targetPath = joinRepoPath(dir, blob.path);
      await ensureParentDirectory(targetPath);
      await FileSystem.writeAsStringAsync(toExpoUri(targetPath), sanitizeGitHubBase64(blobResponse.content), {
        encoding: FileSystem.EncodingType.Base64,
      });

      files[blob.path] = {
        sha: blob.sha,
        mode: blob.mode,
        type: blob.mode === '120000' ? 'symlink' : 'blob',
      };

      loaded += 1;
      onProgress?.({
        phase: 'Receiving objects',
        loaded,
        total: blobs.length,
      } as git.ProgressEvent);
    }

    await this.saveRepoMetadata(dir, {
      version: 1,
      transport: 'github-api',
      repoUrl: repoRef.repoUrl,
      owner: repoRef.owner,
      repo: repoRef.repo,
      branch,
      commitSha,
      treeSha,
      files,
    });
  }

  private async fetchGitHubApiRemoteState(metadata: RepoMetadataFile): Promise<{
    commitSha: string;
    treeSha: string;
    tree: GitHubTreeEntry[];
  }> {
    const branchInfo = await this.githubRequest<{ commit: { sha: string } }>(
      `/repos/${metadata.owner}/${metadata.repo}/branches/${encodeURIComponent(metadata.branch)}`,
      metadata.repoUrl
    );
    const commitSha = branchInfo.commit.sha;

    const commitInfo = await this.githubRequest<{ tree: { sha: string } }>(
      `/repos/${metadata.owner}/${metadata.repo}/git/commits/${commitSha}`,
      metadata.repoUrl
    );
    const treeSha = commitInfo.tree.sha;

    const treeResponse = await this.githubRequest<{ tree: GitHubTreeEntry[] }>(
      `/repos/${metadata.owner}/${metadata.repo}/git/trees/${treeSha}?recursive=1`,
      metadata.repoUrl
    );

    return {
      commitSha,
      treeSha,
      tree: treeResponse.tree,
    };
  }

  private async downloadGitHubBlobToPath(metadata: RepoMetadataFile, blobSha: string, targetPath: string): Promise<void> {
    const blobResponse = await this.githubRequest<{ content: string; encoding: string }>(
      `/repos/${metadata.owner}/${metadata.repo}/git/blobs/${blobSha}`,
      metadata.repoUrl
    );

    await ensureParentDirectory(targetPath);
    await FileSystem.writeAsStringAsync(toExpoUri(targetPath), sanitizeGitHubBase64(blobResponse.content), {
      encoding: FileSystem.EncodingType.Base64,
    });
  }

  private async refreshViaGitHubApi(dir: string): Promise<void> {
    const metadata = await this.loadRepoMetadata(dir);
    if (!metadata) {
      throw new Error('Missing repository metadata');
    }

    const remoteState = await this.fetchGitHubApiRemoteState(metadata);
    const remoteBlobs = remoteState.tree.filter((entry) => entry.type === 'blob');
    const nextFiles: RepoMetadataFile['files'] = { ...metadata.files };

    for (const blob of remoteBlobs) {
      const targetPath = joinRepoPath(dir, blob.path);
      const localInfo = await FileSystem.getInfoAsync(toExpoUri(targetPath));
      const previousEntry = metadata.files[blob.path];

      if (!localInfo.exists) {
        await this.downloadGitHubBlobToPath(metadata, blob.sha, targetPath);
        nextFiles[blob.path] = {
          sha: blob.sha,
          mode: blob.mode,
          type: blob.mode === '120000' ? 'symlink' : 'blob',
        };
        continue;
      }

      if (previousEntry && previousEntry.sha !== blob.sha) {
        const localContentBase64 = await FileSystem.readAsStringAsync(toExpoUri(targetPath), {
          encoding: FileSystem.EncodingType.Base64,
        });
        const localHash = await this.computeBlobSha(localContentBase64);

        if (localHash === previousEntry.sha) {
          await this.downloadGitHubBlobToPath(metadata, blob.sha, targetPath);
          nextFiles[blob.path] = {
            sha: blob.sha,
            mode: blob.mode,
            type: blob.mode === '120000' ? 'symlink' : 'blob',
          };
          continue;
        }
      }

      if (previousEntry) {
        nextFiles[blob.path] = previousEntry;
      } else {
        nextFiles[blob.path] = {
          sha: blob.sha,
          mode: blob.mode,
          type: blob.mode === '120000' ? 'symlink' : 'blob',
        };
      }
    }

    await this.saveRepoMetadata(dir, {
      ...metadata,
      commitSha: remoteState.commitSha,
      treeSha: remoteState.treeSha,
      files: nextFiles,
    });
  }

  private async collectGitHubApiChanges(
    dir: string,
    metadata: RepoMetadataFile,
    changedPaths?: string[]
  ): Promise<{ changedEntries: ChangedEntry[]; deletedEntries: string[] }> {
    const changedEntries: ChangedEntry[] = [];

    if (changedPaths && changedPaths.length > 0) {
      const uniquePaths = [...new Set(changedPaths)];
      const deletedEntries: string[] = [];

      for (const relativePath of uniquePaths) {
        const fullPath = joinRepoPath(dir, relativePath);
        const info = await FileSystem.getInfoAsync(toExpoUri(fullPath));

        if (!info.exists) {
          if (metadata.files[relativePath]) {
            deletedEntries.push(relativePath);
          }
          continue;
        }

        const contentBase64 = await FileSystem.readAsStringAsync(toExpoUri(fullPath), {
          encoding: FileSystem.EncodingType.Base64,
        });
        const existing = metadata.files[relativePath];
        const contentHash = await this.computeBlobSha(contentBase64);

        if (!existing || existing.sha !== contentHash) {
          changedEntries.push({
            path: relativePath,
            sha: contentHash,
            mode: existing?.mode || '100644',
          });
        }
      }

      return { changedEntries, deletedEntries };
    }

    console.log('[sync-github] Listing local files...');
    const localFiles = await listLocalRepositoryFiles(dir);
    console.log('[sync-github] Found', localFiles.length, 'local files');

    const currentFiles = new Set(localFiles);

    console.log('[sync-github] Checking for changes...');
    for (let i = 0; i < localFiles.length; i++) {
      const relativePath = localFiles[i];
      if (i % 50 === 0) {
        console.log(`[sync-github] Processing file ${i + 1}/${localFiles.length}: ${relativePath}`);
      }

      try {
        const contentBase64 = await FileSystem.readAsStringAsync(toExpoUri(joinRepoPath(dir, relativePath)), {
          encoding: FileSystem.EncodingType.Base64,
        });
        const existing = metadata.files[relativePath];
        const contentHash = await this.computeBlobSha(contentBase64);

        if (!existing || existing.sha !== contentHash) {
          changedEntries.push({
            path: relativePath,
            sha: contentHash,
            mode: existing?.mode || '100644',
          });
        }
      } catch (err) {
        console.error(`[sync-github] Error reading file ${relativePath}:`, err);
      }
    }

    const deletedEntries = Object.keys(metadata.files).filter((path) => !currentFiles.has(path));
    return { changedEntries, deletedEntries };
  }

  private async syncViaGitHubApi(dir: string, changedPaths?: string[]): Promise<SyncResult> {
    console.log('[sync-github] Starting sync for:', dir);
    const metadata = await this.loadRepoMetadata(dir);
    if (!metadata) {
      throw new Error('Missing repository metadata');
    }
    console.log('[sync-github] Loaded metadata for:', metadata.owner, metadata.repo);

    const { changedEntries, deletedEntries } = await this.collectGitHubApiChanges(dir, metadata, changedPaths);
    console.log('[sync-github] Changed files:', changedEntries.length, 'Deleted files:', deletedEntries.length);

    if (changedEntries.length === 0 && deletedEntries.length === 0) {
      console.log('[sync-github] No changes to commit');
      return { pulled: true, committed: null, pushed: false };
    }

    console.log('[sync-github] Fetching remote branch info...');
    const latestBranch = await this.githubRequest<{ commit: { sha: string } }>(
      `/repos/${metadata.owner}/${metadata.repo}/branches/${encodeURIComponent(metadata.branch)}`,
      metadata.repoUrl
    );
    const remoteCommitSha = latestBranch.commit.sha;

    console.log('[sync-github] Creating blobs for changed files...');
    const newTreeEntries: Array<Record<string, string | null>> = [];
    const updatedFiles = { ...metadata.files };

    for (let i = 0; i < changedEntries.length; i++) {
      const entry = changedEntries[i];
      console.log(`[sync-github] Creating blob ${i + 1}/${changedEntries.length}: ${entry.path}`);
      
      const contentBase64 = await FileSystem.readAsStringAsync(toExpoUri(joinRepoPath(dir, entry.path)), {
        encoding: FileSystem.EncodingType.Base64,
      });

      const createdBlob = await this.githubRequest<{ sha: string }>(
        `/repos/${metadata.owner}/${metadata.repo}/git/blobs`,
        metadata.repoUrl,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ content: contentBase64, encoding: 'base64' }),
        }
      );

      newTreeEntries.push({
        path: entry.path,
        mode: entry.mode,
        type: 'blob',
        sha: createdBlob.sha,
      });
      updatedFiles[entry.path] = { sha: createdBlob.sha, mode: entry.mode, type: 'blob' };
    }

    for (const path of deletedEntries) {
      // Get the mode from existing metadata if available, otherwise use default
      const existingMode = metadata.files[path]?.mode || '100644';
      newTreeEntries.push({ path, mode: existingMode, sha: null });
      delete updatedFiles[path];
    }

    console.log('[sync-github] Creating new tree...');
    const createdTree = await this.githubRequest<{ sha: string }>(
      `/repos/${metadata.owner}/${metadata.repo}/git/trees`,
      metadata.repoUrl,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ base_tree: remoteCommitSha, tree: newTreeEntries }),
      }
    );

    console.log('[sync-github] Creating commit...');
    const message = `Synapse mobile sync — ${new Date().toISOString()}`;
    const createdCommit = await this.githubRequest<{ sha: string }>(
      `/repos/${metadata.owner}/${metadata.repo}/git/commits`,
      metadata.repoUrl,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message, tree: createdTree.sha, parents: [remoteCommitSha] }),
      }
    );

    console.log('[sync-github] Updating branch reference...');
    try {
      await this.githubRequest(
        `/repos/${metadata.owner}/${metadata.repo}/git/refs/heads/${encodeURIComponent(metadata.branch)}`,
        metadata.repoUrl,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sha: createdCommit.sha, force: false }),
        }
      );
    } catch (error: any) {
      // Handle "not a fast forward" error by merging with remote changes
      if (error?.status === 422 || error?.message?.includes('fast forward')) {
        console.log('[sync-github] Remote has new commits, fetching latest...');
        
        // Get the latest remote commit
        const latestRef = await this.githubRequest<{ object: { sha: string } }>(
          `/repos/${metadata.owner}/${metadata.repo}/git/refs/heads/${encodeURIComponent(metadata.branch)}`,
          metadata.repoUrl,
          { method: 'GET' }
        );
        const latestRemoteSha = latestRef.object.sha;
        
        if (latestRemoteSha !== remoteCommitSha) {
          console.log('[sync-github] Rebasing local changes onto latest remote commit...');

          // Fetch the latest remote commit to get its tree SHA so we can build
          // a correct tree that includes all remote changes (not just our old base).
          const latestRemoteCommit = await this.githubRequest<{ tree: { sha: string } }>(
            `/repos/${metadata.owner}/${metadata.repo}/git/commits/${latestRemoteSha}`,
            metadata.repoUrl,
            { method: 'GET' }
          );

          // Rebuild the tree on top of the latest remote state so no remote
          // changes are silently discarded.
          const rebasedTree = await this.githubRequest<{ sha: string }>(
            `/repos/${metadata.owner}/${metadata.repo}/git/trees`,
            metadata.repoUrl,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ base_tree: latestRemoteCommit.tree.sha, tree: newTreeEntries }),
            }
          );

          // Create a commit whose only parent is the latest remote commit
          // (a clean rebase — no fake merge that would hide missing file content).
          const rebasedCommit = await this.githubRequest<{ sha: string }>(
            `/repos/${metadata.owner}/${metadata.repo}/git/commits`,
            metadata.repoUrl,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                message: `${message} (rebased on remote changes)`,
                tree: rebasedTree.sha,
                parents: [latestRemoteSha],
              }),
            }
          );

          // This is now a fast-forward from latestRemoteSha, so force:false is safe.
          await this.githubRequest(
            `/repos/${metadata.owner}/${metadata.repo}/git/refs/heads/${encodeURIComponent(metadata.branch)}`,
            metadata.repoUrl,
            {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ sha: rebasedCommit.sha, force: false }),
            }
          );

          console.log('[sync-github] Successfully pushed rebased commit:', rebasedCommit.sha);

          const nextMetadata: RepoMetadataFile = {
            ...metadata,
            commitSha: rebasedCommit.sha,
            treeSha: rebasedTree.sha,
            files: updatedFiles,
          };
          await this.saveRepoMetadata(dir, nextMetadata);

          return { pulled: true, committed: rebasedCommit.sha, pushed: true };
        }
      }
      
      // If it's not a fast forward error or merging failed, rethrow
      throw error;
    }

    console.log('[sync-github] Saving updated metadata...');
    const nextMetadata: RepoMetadataFile = {
      ...metadata,
      commitSha: createdCommit.sha,
      treeSha: createdTree.sha,
      files: updatedFiles,
    };
    await this.saveRepoMetadata(dir, nextMetadata);

    console.log('[sync-github] Sync complete! Commit:', createdCommit.sha);
    return { pulled: true, committed: createdCommit.sha, pushed: true };
  }

  private async computeBlobSha(contentBase64: string): Promise<string> {
    const bytes = base64ToUint8(contentBase64);
    const { oid } = await git.hashBlob({ object: bytes });
    return oid;
  }

  // Authentication Methods
  static async setCredentials(repoUrl: string, username: string, token: string): Promise<void> {
    const existingData = await AsyncStorage.getItem(CREDENTIALS_KEY);
    const credentials: CredentialsMap = existingData ? JSON.parse(existingData) : {};
    
    credentials[repoUrl] = { username, token };
    
    await AsyncStorage.setItem(CREDENTIALS_KEY, JSON.stringify(credentials));
  }

  static async getCredentials(repoUrl: string): Promise<GitCredentials | null> {
    const data = await AsyncStorage.getItem(CREDENTIALS_KEY);
    if (!data) {
      return null;
    }

    const credentials: CredentialsMap = JSON.parse(data);
    return credentials[repoUrl] || null;
  }

  static async clearCredentials(): Promise<void> {
    await AsyncStorage.removeItem(CREDENTIALS_KEY);
  }

  // Git Operations
  async clone(
    url: string,
    dir: string,
    onProgress?: git.ProgressCallback
  ): Promise<void> {
    try {
      const repoRef = parseGitHubRepo(url);
      if (repoRef) {
        await this.cloneViaGitHubApi(repoRef, dir, onProgress);
        console.log('[clone] completed successfully');
        return;
      }

      await git.clone({
        fs,
        http,
        dir,
        url,
        onProgress: (evt) => {
          console.log('[clone-progress]', evt.phase, evt.loaded, '/', evt.total);
          if (onProgress) onProgress(evt);
        },
        singleBranch: true,
        noTags: true,
        depth: 1,
        onAuth: await GitService.getAuthCallback(url),
      });
      console.log('[clone] completed successfully');
    } catch (error) {
      const err = error as any;
      console.log('[clone-error] message:', err?.message);
      console.log('[clone-error] caller:', err?.caller);
      console.log('[clone-error] stack:', err?.stack?.split('\n').slice(0, 12).join('\n'));
      this.handleError(err as Error, 'Clone');
    }
  }

  async pull(dir: string): Promise<void> {
    try {
      const remoteUrl = await this.getRemoteUrl(dir);

      await git.pull({
        fs,
        http,
        dir,
        fastForwardOnly: false,
        singleBranch: true,
        noTags: true,
        onAuth: await GitService.getAuthCallback(remoteUrl),
      });
    } catch (error) {
      const errorType = getGitErrorType(error as Error);
      if (errorType === GitErrorType.CONFLICT) {
        // Stage and commit conflicted files so conflicts appear in the editor
        const status = await git.statusMatrix({ fs, dir });
        for (const [filepath, , workdirStatus] of status) {
          if (workdirStatus !== 0) {
            await git.add({ fs, dir, filepath });
          }
        }
        const timestamp = new Date().toISOString();
        await git.commit({
          fs,
          dir,
          message: `Synapse: merge conflict — ${timestamp}`,
          author: { name: 'Synapse Mobile', email: 'mobile@synapse.local' },
        });
        return;
      }
      this.handleError(error as Error, 'Pull');
    }
  }

  async commit(dir: string): Promise<string | null> {
    try {
      const status = await git.statusMatrix({ fs, dir });
      
      let hasChanges = false;
      const modifiedFiles: string[] = [];
      const deletedFiles: string[] = [];
      
      for (const [filepath, headStatus, workdirStatus, stageStatus] of status) {
        if (workdirStatus !== stageStatus) {
          hasChanges = true;
          
          if (workdirStatus === 0) {
            deletedFiles.push(filepath);
            await git.remove({ fs, dir, filepath });
          } else {
            modifiedFiles.push(filepath);
            await git.add({ fs, dir, filepath });
          }
        }
      }
      
      if (!hasChanges) {
        return null;
      }
      
      const timestamp = new Date().toISOString();
      const message = `Synapse mobile sync — ${timestamp}`;
      
      const sha = await git.commit({
        fs,
        dir,
        message,
        author: {
          name: 'Synapse Mobile',
          email: 'mobile@synapse.local',
        },
      });
      
      return sha;
    } catch (error) {
      this.handleError(error as Error, 'Commit');
    }
  }

  async push(dir: string): Promise<void> {
    try {
      const remoteUrl = await this.getRemoteUrl(dir);
      const currentBranch = await git.currentBranch({ fs, dir, fullname: false });
      
      await git.push({
        fs,
        http,
        dir,
        remote: 'origin',
        ref: currentBranch || 'main',
        onAuth: await GitService.getAuthCallback(remoteUrl),
      });
    } catch (error) {
      this.handleError(error as Error, 'Push');
    }
  }

  async sync(dir: string, changedPaths?: string[]): Promise<SyncResult> {
    const repoMetadata = await this.loadRepoMetadata(dir).catch(() => null);
    if (repoMetadata?.transport === 'github-api') {
      try {
        return await this.syncViaGitHubApi(dir, changedPaths);
      } catch (error) {
        this.handleError(error as Error, 'Sync');
      }
    }

    let pulled = false;
    let committed: string | null = null;
    let pushed = false;
    
    try {
      await this.pull(dir);
      pulled = true;
    } catch (error) {
      console.warn('Pull failed during sync:', error);
    }
    
    committed = await this.commit(dir);
    
    if (committed) {
      try {
        await this.push(dir);
        pushed = true;
      } catch (error) {
        console.warn('Push failed during sync:', error);
      }
    }
    
    return { pulled, committed, pushed };
  }

  async refreshRemote(dir: string): Promise<void> {
    const repoMetadata = await this.loadRepoMetadata(dir).catch(() => null);
    if (repoMetadata?.transport === 'github-api') {
      try {
        await this.refreshViaGitHubApi(dir);
        return;
      } catch (error) {
        this.handleError(error as Error, 'Refresh');
      }
    }

    await this.pull(dir);
  }

  // Helper Methods
  async getStatus(dir: string): Promise<StatusResult> {
    try {
      const status = await git.statusMatrix({ fs, dir });
      
      const modified: string[] = [];
      const deleted: string[] = [];
      const added: string[] = [];
      
      for (const [filepath, headStatus, workdirStatus, stageStatus] of status) {
        if (workdirStatus !== stageStatus) {
          if (headStatus === 0) {
            added.push(filepath);
          } else if (workdirStatus === 0) {
            deleted.push(filepath);
          } else {
            modified.push(filepath);
          }
        }
      }
      
      return {
        modified,
        deleted,
        added,
        hasChanges: modified.length > 0 || deleted.length > 0 || added.length > 0,
      };
    } catch (error) {
      this.handleError(error as Error, 'Get status');
    }
  }

  async hasChanges(dir: string): Promise<boolean> {
    const status = await this.getStatus(dir);
    return status.hasChanges;
  }

  async isRepository(dir: string): Promise<boolean> {
    if (await this.isGitHubApiRepository(dir)) {
      return true;
    }

    try {
      await git.currentBranch({ fs, dir, fullname: false });
      return true;
    } catch {
      return false;
    }
  }

  private async getRemoteUrl(dir: string): Promise<string> {
    try {
      const remote = await git.getConfig({ fs, dir, path: 'remote.origin.url' });
      return remote?.value || '';
    } catch {
      return '';
    }
  }

  /** Walk trees to resolve a repo-relative path to a blob oid at a commit (isomorphic-git trees use basename `path`). */
  private async resolveBlobOidAtCommit(
    dir: string,
    commitSha: string,
    relativePath: string
  ): Promise<string | null> {
    const parts = relativePath.split('/').filter((p) => p.length > 0);
    if (parts.length === 0) {
      return null;
    }
    const commit = await git.readCommit({ fs, dir, oid: commitSha });
    let treeOid = commit.commit.tree;
    for (let i = 0; i < parts.length; i++) {
      const tree = await git.readTree({ fs, dir, oid: treeOid });
      const name = parts[i];
      const entry = tree.tree.find((e) => e.path === name);
      if (!entry) {
        return null;
      }
      const last = i === parts.length - 1;
      if (last) {
        return entry.type === 'blob' ? entry.oid : null;
      }
      if (entry.type !== 'tree') {
        return null;
      }
      treeOid = entry.oid;
    }
    return null;
  }

  private async getFileContentFromGitRepo(
    dir: string,
    relativePath: string,
    commitSha: string
  ): Promise<string | null> {
    const blobOid = await this.resolveBlobOidAtCommit(dir, commitSha, relativePath);
    if (!blobOid) {
      return null;
    }
    const { blob } = await git.readBlob({ fs, dir, oid: blobOid });
    return Buffer.from(blob).toString('utf-8');
  }

  /** Per-file commit list via GitHub API (Synapse “GitHub API” vaults have no local .git objects for isomorphic-git log). */
  private async getFileHistoryGitHubApi(
    dir: string,
    relativePath: string
  ): Promise<Array<{ sha: string; message: string; date: Date }>> {
    const meta = await this.loadRepoMetadata(dir);
    if (!meta) {
      return [];
    }
    const pathQuery = `?sha=${encodeURIComponent(meta.branch)}&per_page=100&path=${encodeURIComponent(relativePath)}`;
    const commits = await this.githubRequest<
      Array<{
        sha: string;
        commit: { message: string; committer?: { date?: string }; author?: { date?: string } };
      }>
    >(`/repos/${meta.owner}/${meta.repo}/commits${pathQuery}`, meta.repoUrl);
    return commits.map((c) => ({
      sha: c.sha,
      message: c.commit.message.trim().split('\n')[0],
      date: new Date(c.commit.committer?.date || c.commit.author?.date || 0),
    }));
  }

  private async getFileContentAtCommitGitHubApi(
    dir: string,
    relativePath: string,
    commitSha: string
  ): Promise<string | null> {
    try {
      const meta = await this.loadRepoMetadata(dir);
      if (!meta) {
        return null;
      }
      const encodedPath = relativePath
        .split('/')
        .map((seg) => encodeURIComponent(seg))
        .join('/');
      const data = await this.githubRequest<
        { content?: string; encoding?: string } | unknown[]
      >(`/repos/${meta.owner}/${meta.repo}/contents/${encodedPath}?ref=${encodeURIComponent(commitSha)}`, meta.repoUrl);
      if (Array.isArray(data)) {
        return null;
      }
      const file = data as { content?: string; encoding?: string };
      if (file.encoding === 'base64' && file.content) {
        return Buffer.from(sanitizeGitHubBase64(file.content), 'base64').toString('utf-8');
      }
      return null;
    } catch (e) {
      console.error('[getFileContentAtCommitGitHubApi]', e);
      return null;
    }
  }

  /**
   * Commit history for one file (same idea as macOS `git log -- path`).
   * @param dir - Repository root URI
   * @param filePath - Path relative to repo root
   */
  async getFileHistory(
    dir: string,
    filePath: string
  ): Promise<Array<{ sha: string; message: string; date: Date }>> {
    const repoDir = toExpoUri(dir);
    const pathInRepo = filePath.replace(/^\/+/, '');
    if (!pathInRepo) {
      return [];
    }
    try {
      if (await this.isGitHubApiRepository(repoDir)) {
        return await this.getFileHistoryGitHubApi(repoDir, pathInRepo);
      }
      const commits = await git.log({
        fs,
        dir: repoDir,
        filepath: pathInRepo,
        ref: 'HEAD',
      });

      return commits.map((commit) => ({
        sha: commit.oid,
        message: commit.commit.message.trim().split('\n')[0],
        date: new Date(commit.commit.committer.timestamp * 1000),
      }));
    } catch (error) {
      if ((error as Error).message?.includes('no such file or directory')) {
        return [];
      }
      return [];
    }
  }

  /**
   * File contents at a commit (macOS: `git show sha:path`).
   * @param dir - Repository root URI
   * @param filePath - Path relative to repo root
   */
  async getFileContentAtCommit(
    dir: string,
    filePath: string,
    commitSha: string
  ): Promise<string | null> {
    const repoDir = toExpoUri(dir);
    const pathInRepo = filePath.replace(/^\/+/, '');
    if (!pathInRepo || !commitSha) {
      return null;
    }
    try {
      if (await this.isGitHubApiRepository(repoDir)) {
        return await this.getFileContentAtCommitGitHubApi(repoDir, pathInRepo, commitSha);
      }
      return await this.getFileContentFromGitRepo(repoDir, pathInRepo, commitSha);
    } catch (error) {
      console.error('[getFileContentAtCommit] Error:', error);
      return null;
    }
  }

  // Static wrappers for convenience
  static async clone(
    url: string,
    dir: string,
    onProgress?: git.ProgressCallback
  ): Promise<void> {
    return GitService.getInstance().clone(url, dir, onProgress);
  }

  static async pull(dir: string): Promise<void> {
    return GitService.getInstance().pull(dir);
  }

  static async refreshRemote(dir: string): Promise<void> {
    return GitService.getInstance().refreshRemote(dir);
  }

  static async commit(dir: string): Promise<string | null> {
    return GitService.getInstance().commit(dir);
  }

  static async push(dir: string): Promise<void> {
    return GitService.getInstance().push(dir);
  }

  static async sync(dir: string, changedPaths?: string[]): Promise<SyncResult> {
    return GitService.getInstance().sync(dir, changedPaths);
  }

  static async getStatus(dir: string): Promise<StatusResult> {
    return GitService.getInstance().getStatus(dir);
  }

  static async hasChanges(dir: string): Promise<boolean> {
    return GitService.getInstance().hasChanges(dir);
  }

  static async isRepository(dir: string): Promise<boolean> {
    return GitService.getInstance().isRepository(dir);
  }

  static async getFileHistory(
    dir: string,
    filePath: string
  ): Promise<Array<{ sha: string; message: string; date: Date }>> {
    return GitService.getInstance().getFileHistory(dir, filePath);
  }

  static async getFileContentAtCommit(
    dir: string,
    filePath: string,
    commitSha: string
  ): Promise<string | null> {
    return GitService.getInstance().getFileContentAtCommit(dir, filePath, commitSha);
  }
}
