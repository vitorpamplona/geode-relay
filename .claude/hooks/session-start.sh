#!/bin/bash
# Session start hook: Configure proxy auth and SSL trust for Claude Code on the web
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# --- Proxy credentials: configure Maven/Gradle if authenticated proxy is set ---
proxy="${https_proxy:-${HTTPS_PROXY:-}}"
if [ -n "$proxy" ] && echo "$proxy" | grep -q '@'; then
  rest="${proxy#*://}"
  userpass="${rest%@*}"
  hostport="${rest##*@}"
  user="${userpass%%:*}"
  pass="${userpass#*:}"
  host="${hostport%%:*}"
  port="${hostport##*:}"
  port="${port%/}"

  mkdir -p ~/.m2
  cat > ~/.m2/settings.xml << EOF
<settings>
  <proxies>
    <proxy>
      <id>ccw</id><active>true</active><protocol>https</protocol>
      <host>$host</host><port>$port</port>
      <username>$user</username>
      <password><![CDATA[$pass]]></password>
    </proxy>
  </proxies>
</settings>
EOF

  # Force wagon transport for Maven 3.9+ proxy auth compatibility
  cat > ~/.mavenrc << 'MAVENRC'
MAVEN_OPTS="$MAVEN_OPTS -Dmaven.resolver.transport=wagon"
MAVENRC

  mkdir -p ~/.gradle
  cat > ~/.gradle/gradle.properties << EOF
systemProp.https.proxyHost=$host
systemProp.https.proxyPort=$port
systemProp.https.proxyUser=$user
systemProp.https.proxyPassword=$pass
systemProp.http.proxyHost=$host
systemProp.http.proxyPort=$port
systemProp.http.proxyUser=$user
systemProp.http.proxyPassword=$pass
# Override nonProxyHosts: route all external traffic (incl. *.google.com) through proxy
systemProp.http.nonProxyHosts=localhost|127.0.0.1
systemProp.https.nonProxyHosts=localhost|127.0.0.1
# Use Ubuntu's Java trust store (includes Anthropic TLS inspection CA) for all Gradle JVMs.
# This is needed because Gradle may download a custom JDK (e.g. JetBrains) whose bundled
# trust store doesn't include the Anthropic CA, causing TLS inspection failures.
systemProp.javax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts
systemProp.javax.net.ssl.trustStoreType=JKS
systemProp.javax.net.ssl.trustStorePassword=changeit
systemProp.jdk.http.auth.tunneling.disabledSchemes=
systemProp.jdk.http.auth.proxying.disabledSchemes=
EOF

  echo "Configured Maven/Gradle proxy from HTTPS_PROXY" >&2
fi

# --- SSL trust: import Anthropic TLS inspection CA into JVM trust stores ---
ANTHROPIC_CA_PEM=$(python3 -c "
import re, ssl, sys
try:
    with open('/etc/ssl/certs/ca-certificates.crt') as f:
        certs = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', f.read(), re.DOTALL)
    for cert in certs:
        der = ssl.PEM_cert_to_DER_cert(cert)
        if b'Anthropic' in der and b'sandbox-egress-production' in der:
            print(cert)
            break
except Exception as e:
    sys.stderr.write(f'CA extraction failed: {e}\n')
" 2>/dev/null)

if [ -n "$ANTHROPIC_CA_PEM" ]; then
  TMPCA=$(mktemp /tmp/anthropic-ca.XXXXXX.pem)
  echo "$ANTHROPIC_CA_PEM" > "$TMPCA"
  for cacerts in \
    /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
    /root/.gradle/jdks/*/lib/security/cacerts; do
    [ -f "$cacerts" ] || continue
    keytool -list -keystore "$cacerts" -storepass changeit \
      -alias anthropic-egress-production-ca >/dev/null 2>&1 && continue
    keytool -import \
      -alias anthropic-egress-production-ca \
      -file "$TMPCA" \
      -keystore "$cacerts" \
      -storepass changeit \
      -noprompt >/dev/null 2>&1 && \
      echo "Imported Anthropic CA into $cacerts" >&2
  done
  rm -f "$TMPCA"
fi

# geode and relayBench are JVM-only: no Android SDK or Kotlin/Native toolchain to
# install. Warm the Gradle distribution so the first build doesn't pay for it.
cd "${CLAUDE_PROJECT_DIR:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
./gradlew --version > /dev/null 2>&1

echo "geode-relay session setup complete."
