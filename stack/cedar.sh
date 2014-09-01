#!/bin/bash

exec 2>&1
set -e
set -x

cat > /etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu lucid main
deb http://archive.ubuntu.com/ubuntu lucid-security main
deb http://archive.ubuntu.com/ubuntu lucid-updates main
deb http://archive.ubuntu.com/ubuntu lucid universe
EOF

apt-get update

xargs apt-get install -y --force-yes < packages.txt

# pull in a newer libpq
echo "deb http://apt.postgresql.org/pub/repos/apt/ lucid-pgdg 9.2" >> /etc/apt/sources.list

cat > /etc/apt/preferences <<EOF
Package: *
Pin: release a=lucid-pgdg
Pin-Priority: -10
EOF

curl -o /tmp/postgres.asc http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc
if [ "$(sha256sum /tmp/postgres.asc)" = \
    "fbdb6c565cd95957b645197686587f7735149383a3d5e1291b6830e6730e672f" ]; then
    apt-key add /tmp/postgres.asc
fi

apt-get update
apt-get install -y --force-yes -t lucid-pgdg libpq5 libpq-dev

function fetch_verify_tarball() {
    cd /tmp
    local tarball=$(basename $1)
    curl --location --output $tarball $1
    if [ "$(sha256sum $tarball)" != "$2" ]; then
        echo "Checksum mismatch for $1!"
        # exit 1
    fi
    tar xzf $tarball
}

fetch_verify_tarball "http://www.python.org/ftp/python/2.7.6/Python-2.7.6.tgz" \
    "99c6860b70977befa1590029fae092ddb18db1d69ae67e8b9385b66ed104ba58  Python-2.7.6.tgz"
cd Python-2.7.6 && ./configure && make && make install

fetch_verify_tarball "http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p547.tar.gz" \
    "9ba118e4aba04c430bc4d5efb09b31a0277e101c9fd2ef3b80b9c684d7ae57a1  ruby-1.9.3-p547.tar.gz"
cd ruby-1.9.3-p547 && ./configure --prefix=/usr/local && make && make install

cd /
rm -rf /var/cache/apt/archives/*.deb
#rm -rf /var/lib/apt/lists/*
rm -rf /root/*
rm -rf /tmp/*

apt-get clean

# remove SUID and SGID flags from all binaries
function pruned_find() {
  find / -type d \( -name dev -o -name proc \) -prune -o $@ -print
}

pruned_find -perm /u+s | xargs -r chmod u-s
pruned_find -perm /g+s | xargs -r chmod g-s

# remove non-root ownership of files
chown root:root /var/lib/libuuid

# display build summary
set +x
echo -e "\nRemaining suspicious security bits:"
(
  pruned_find ! -user root
  pruned_find -perm /u+s
  pruned_find -perm /g+s
  pruned_find -perm /+t
) | sed -u "s/^/  /"

echo -e "\nInstalled versions:"
(
  git --version
  java -version
  ruby -v
  gem -v
  python -V
) | sed -u "s/^/  /"

echo -e "\nSuccess!"
exit 0
