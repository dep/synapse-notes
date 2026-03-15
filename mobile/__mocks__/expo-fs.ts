// Mock expo-fs for React Native testing
const mockStat = {
  type: 'file',
  mode: 0o644,
  size: 100,
  ino: 1,
  mtimeMs: Date.now(),
  ctimeMs: Date.now(),
  uid: 0,
  gid: 0,
  dev: 0,
  isFile: jest.fn(() => true),
  isDirectory: jest.fn(() => false),
  isSymbolicLink: jest.fn(() => false),
};

const mockPromises = {
  mkdir: jest.fn(() => Promise.resolve()),
  rmdir: jest.fn(() => Promise.resolve()),
  readdir: jest.fn(() => Promise.resolve([])),
  writeFile: jest.fn(() => Promise.resolve()),
  readFile: jest.fn(() => Promise.resolve('')),
  unlink: jest.fn(() => Promise.resolve()),
  rename: jest.fn(() => Promise.resolve()),
  stat: jest.fn(() => Promise.resolve(mockStat)),
  lstat: jest.fn(() => Promise.resolve(mockStat)),
  symlink: jest.fn(() => { throw new Error('Not implemented'); }),
  readlink: jest.fn(() => { throw new Error('Not implemented'); }),
};

export default {
  promises: mockPromises,
};

export { mockPromises as promises };
