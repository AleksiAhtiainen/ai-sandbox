{ ... }:

{
  # JetBrains' launcher reads this file if it exists, otherwise falls back to
  # built-in defaults — so pointing at the share unconditionally is safe.
  environment.sessionVariables.IDEA_VM_OPTIONS = "/mnt/share/idea64.vmoptions";
}
