type RepositoryRefreshListener = (repositoryPath: string) => void | Promise<void>;

const repositoryRefreshListeners = new Set<RepositoryRefreshListener>();

export const subscribeToRepositoryRefresh = (listener: RepositoryRefreshListener) => {
  repositoryRefreshListeners.add(listener);

  return () => {
    repositoryRefreshListeners.delete(listener);
  };
};

export const emitRepositoryRefresh = async (repositoryPath: string) => {
  await Promise.all(
    Array.from(repositoryRefreshListeners).map((listener) => listener(repositoryPath))
  );
};
