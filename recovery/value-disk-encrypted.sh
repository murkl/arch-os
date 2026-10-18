# A LUKS header is readable without the password.
[ "$(fstype "$(target_partition)")" = "crypto_LUKS" ] && echo true || echo false
