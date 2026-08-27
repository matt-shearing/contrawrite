#!/bin/bash
# Omarchy post-update stub. The runner copies this file; exec the checkout.
exec "${CONTRAWRITE_ROOT:-$HOME/dev/contrawrite}/bin/sync" --from-hook "$@"
