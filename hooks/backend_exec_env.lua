-- Skills add nothing to the environment.
function PLUGIN:BackendExecEnv(ctx)
    return { env_vars = {} }
end
