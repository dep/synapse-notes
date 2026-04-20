import type { GitTreeEntry } from './contents'

export type TreeNode = {
  name: string
  path: string
  type: 'blob' | 'tree'
  children: TreeNode[]
}

export function buildTree(entries: GitTreeEntry[]): TreeNode {
  const root: TreeNode = { name: '', path: '', type: 'tree', children: [] }
  const index = new Map<string, TreeNode>()
  index.set('', root)

  const sorted = [...entries].sort((a, b) => a.path.localeCompare(b.path))
  for (const entry of sorted) {
    const parts = entry.path.split('/')
    const name = parts[parts.length - 1]
    const parentPath = parts.slice(0, -1).join('/')
    const parent = index.get(parentPath) ?? root
    const node: TreeNode = {
      name,
      path: entry.path,
      type: entry.type,
      children: [],
    }
    parent.children.push(node)
    if (entry.type === 'tree') index.set(entry.path, node)
  }

  sortChildren(root)
  return root
}

function sortChildren(node: TreeNode): void {
  node.children.sort((a, b) => {
    if (a.type !== b.type) return a.type === 'tree' ? -1 : 1
    return a.name.localeCompare(b.name)
  })
  for (const child of node.children) sortChildren(child)
}

export function isMarkdownPath(path: string): boolean {
  return /\.(md|mdx|markdown)$/i.test(path)
}
