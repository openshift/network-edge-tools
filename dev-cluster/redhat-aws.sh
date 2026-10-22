# ~/bin/redhat-aws.sh  (SOURCE THIS FILE)
# shellcheck disable=SC2034

# --- settings ---
# Account: NIDS Team AWS Dev (Account ID provided via AWS_ACCOUNT_ID env var)
PROFILE="${PROFILE:-nids-dev}"
REGION="${REGION:-us-west-2}"
KERBEROS_ID="${KERBEROS_ID:-$USER}"
SAML_ROLE_NAME="${SAML_ROLE_NAME:-}"
VENV_PATH="${VENV_PATH:-$HOME/.aws-saml-venv}"
# -----------------

# must be sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ERROR: this script must be sourced, not run directly."
  echo "Usage: source $0"
  exit 1
fi

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
    echo "ERROR: AWS_ACCOUNT_ID environment variable is not set." >&2
    echo "       Please ask the NIDS team for the AWS Account ID on Slack and export it:" >&2
    echo "       export AWS_ACCOUNT_ID=\"<account_id>\"" >&2
    return 1
fi

if [[ -z "${SAML_ROLE_NAME:-}" ]]; then
    SAML_ROLE_NAME="admin"
fi

if [[ "${SAML_ROLE_NAME}" != "${AWS_ACCOUNT_ID}-"* ]]; then
    SAML_ROLE_NAME="${AWS_ACCOUNT_ID}-${SAML_ROLE_NAME}"
fi

echo "==> clearing AWS_* env vars in this shell"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
      AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_DEFAULT_PROFILE 2>/dev/null || true
unset -m 'AWS_*' 2>/dev/null || true

# 1) Check Kerberos ticket
echo "==> verifying Kerberos ticket..."
KINIT_OPTS=""
# Optional: look for a password file in project root or home to skip prompt
PASSWD_FILE="${PWD}/.krb-passwd"
[[ ! -f "$PASSWD_FILE" ]] && PASSWD_FILE="${HOME}/.krb-passwd"

if [[ -f "$PASSWD_FILE" ]]; then
    echo "    Using Kerberos password file: $PASSWD_FILE"
    KINIT_OPTS="--password-file=$PASSWD_FILE"
fi

if ! klist -s; then
    echo "==> No active Kerberos ticket found. Please authenticate:"
    kinit $KINIT_OPTS "${KERBEROS_ID}@IPA.REDHAT.COM" || return 1
fi

# 2. Check if AWS token is valid (or force refresh)
export AWS_PROFILE="$PROFILE"
echo "==> checking AWS session for profile: $AWS_PROFILE"
if [[ "${FRESH_SESSION:-}" == "true" ]]; then
    echo "==> FRESH_SESSION requested. Forcing refresh via aws-saml.py..."
    REFRESH_NEEDED=true
elif ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "==> session expired or not found. refreshing via aws-saml.py..."
    REFRESH_NEEDED=true
else
    REFRESH_NEEDED=false
fi

if [[ "$REFRESH_NEEDED" == "true" ]]; then
    # Check if we are in the container or need the local venv
    if command -v aws-saml.py >/dev/null 2>&1; then
        # Container environment: use system aws-saml.py
        aws-saml.py --target-account "$AWS_ACCOUNT_ID" \
                    --target-role "$SAML_ROLE_NAME" \
                    --session-duration 14400 \
                    --profile "$AWS_PROFILE"
    else
        # Local environment (legacy support)
        if [[ ! -d "$VENV_PATH" ]]; then
            echo "ERROR: SAML virtualenv not found at $VENV_PATH" >&2
            echo "Please run ./setup.sh first to initialize the environment." >&2
            return 1
        fi
        (
            source "$VENV_PATH/bin/activate"
            aws-saml.py --target-account "$AWS_ACCOUNT_ID" \
                        --target-role "$SAML_ROLE_NAME" \
                        --session-duration 14400 \
                        --profile "$AWS_PROFILE"
        )
    fi
fi


# helper that always ignores any stray AWS_* for the call
aws_clean () {
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
      -u AWS_REGION -u AWS_DEFAULT_REGION -u AWS_PROFILE -u AWS_DEFAULT_PROFILE \
      aws "$@"
}

echo "==> verification"
aws configure list --profile "$AWS_PROFILE"

echo "==> identity"
aws sts get-caller-identity --profile "$AWS_PROFILE"

echo "Ready. This shell is now on profile: $AWS_PROFILE"
