export function defaultCommitMessage(
  action: 'update' | 'create' | 'delete' | 'rename',
  path: string,
  renamedTo?: string,
): string {
  switch (action) {
    case 'update':
      return `Update ${path}`
    case 'create':
      return `Create ${path}`
    case 'delete':
      return `Delete ${path}`
    case 'rename':
      return `Rename ${path} to ${renamedTo ?? ''}`.trim()
  }
}
