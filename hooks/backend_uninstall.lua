local links = require("links")

function PLUGIN:BackendUninstall(ctx)
    links.uninstall(ctx.install_path)
end
