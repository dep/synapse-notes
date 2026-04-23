import type { TreeNode } from '../github/tree'

export function parentFolder(path: string): string {
  if (!path) return ''
  const slash = path.lastIndexOf('/')
  return slash >= 0 ? path.slice(0, slash) : ''
}

export type BreadcrumbSegment = {
  label: string
  path: string
}

export function breadcrumbSegments(folder: string): BreadcrumbSegment[] {
  const out: BreadcrumbSegment[] = [{ label: 'Root', path: '' }]
  if (!folder) return out
  const parts = folder.split('/')
  let acc = ''
  for (const part of parts) {
    acc = acc ? `${acc}/${part}` : part
    out.push({ label: part, path: acc })
  }
  return out
}

export function findFolderNode(root: TreeNode, folder: string): TreeNode | null {
  if (!folder) return root
  const parts = folder.split('/')
  let node: TreeNode | undefined = root
  for (const part of parts) {
    node = node?.children.find(
      (c) => c.type === 'tree' && c.name === part,
    )
    if (!node) return null
  }
  return node
}
