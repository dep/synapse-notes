// Token stored in localStorage so it survives tab close / page reload.
export const GITHUB_TOKEN_STORAGE_KEY = 'synapse_github_token'
// Short-lived OAuth state; must not leak across tabs, so sessionStorage.
export const OAUTH_STATE_SESSION_KEY = 'synapse_oauth_state'
export const REPO_SELECTION_LOCAL_KEY = 'synapse_selected_repo'
