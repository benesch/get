#!/bin/sh

set -eu

die() {
	echo "$@" >&2
	exit 1
}

usage() {
	cat <<EOF
usage: get [--os=<os>] [--install=[<path>]]
            [--version=<sha|tag>] [--edge[=<release>]] [--prerelease]
		   [<binary>]

By default, get downloads the latest stable version of CockroachDB for your
host operating system and architecture into your current directory:

    $ get

To fetch the latest prerelease (i.e., an alpha or beta) instead:

    $ get --prerelease

To fetch a bleeding-edge binary:

    $ get --edge
    $ get --edge=2.0

To fetch a specific version:

    $ get --version=a1c3d3f
    $ get --version=v1.1.5

To download a binary for a different operating system:

    $ get --os=linux-gnu

To install a binary into /usr/local/bin, or a location of your choosing:

    $ get --install
    $ get --install=/usr/bin

get can also download several other CockroachDB-related binaries:

    $ get kv
    $ get workload

To see all available binaries:

    $ get --list
EOF
}

# Parse arguments.
binary= 
os=
arch=
sha=
edge=false
prerelease=false
help=false

next=
for arg
do
	if [[ -n "$next" ]]; then
		eval "$next=\$arg"
		next=
		shift
		continue
	fi
	case "$arg" in
		--o|--os) next=os;;
		--a|--ar|--arc|--arch) next=arch;;
		--s|--sh|--sha) next=sha;;
		--e|--ed|--edg|--edge) edge=true;;
		--p|--pr|--pre|--prer|--prere|--prerel|--prerele|--prerelea|--prereleas|--prerelease) prerelease=true;;
		--h|--he|--hel|--help) help=true;;
		--o=*|--os=*) os=${arg#*=};;
		--a=*|--ar=*|--arc=*|--arch=*) arch=${arg#*=};;
		--s=*|--sh=*|--sha=*) sha=${sha#*=};;
		--*) unknown option "$arg";;
		--) break;;
		-*)
			OPTIND=1
			getopts :o:s:eph opt
			case "$opt" in
				o) os="$OPTARG" ;;
				s) sha="$OPTARG" ;;
				e) edge=true ;;
				p) prerelease=true ;;
				h) help=true;;
				:) echo "option $1 requires an argument"; exit 1 ;;
				*) die "unknown option $1";;
			esac
			if [[ "$OPTIND" != 1 ]]; then
				next=discard
			fi
			;;
		*)
			if [[ -z "$binary" ]]
			then
				binary="$arg"
			else
				usage >&2
				exit 1
			fi
			;;
	esac
	shift
done

if "$help"; then
	usage
	exit 0
fi

echo "os: $os, arch $arch, sha $sha, prerelease $prerelease, edge $edge, help $help, binary $binary"
exit 1

latest_stable=v1.1.4
latest_prerelease=v2.0-alpha.20180122

if "$prerelease"; then
	if [ -z "$sha" ] && ! "$edge"; then
		version=$latest_prerelease
	elif "$edge"; then
		die "-s and -p cannot be specified together"
	else
		die "-e and -p cannot be specified together"
	fi
else
	if [ -z "$sha" ]; then
		if "$edge"; then
			redir=$(curl -If https://edge-binaries.cockroachdb.com/cockroach/cockroach.darwin-amd64.LATEST)
			header=$(echo "$redir" | grep -E 'Location: /cockroach/cockroach.darwin-amd64\.[a-z0-9]{40}')
			sha=$(echo "$header" | cut -d. -f3)
			version=$(echo "$sha" | cut -c 1-9)
		else
			version=$latest_stable
		fi
	else
		version=$(echo "$sha" | cut -c 1-9)
	fi
fi

# Detect operating system.
if [ -z "$uname" ]; then
	uname=$(uname)
fi
case "$uname" in
	[Ll]inux)
		if ldd --version 2>&1 | grep GLIBC; then    
			os=linux-gnu
			abi=
		else
			os=linux-musl
			abi=
		fi
		;;
	[Dd]arwin|mac|macos)
		os=darwin
		abi=10.9-
		;;
	CYGWIN|MINGW|win32|windows)
		os=windows
		abi=6.2-
		;;
	*)
		die "unsupported operating system: $uname"
		;;
esac

# Detect architecture.
uname_m=$(uname -m)
case "$uname_m" in
	x86_64|amd64)
		arch=amd64
		;;
	*)
		die "unsupported architecture: $uname_m"
		;;
esac

out="cockroach-$version"
if [ os = windows ]; then
	out+=.exe
fi
if [ -z "$sha" ]; then
	path="cockroach-$version.$os-$abi$arch"
	url="https://binaries.cockroachdb.com/$path.tgz"
	echo "Downloading $url..."
	tmp=$(mktemp)
	trap "rm -f $tmp" EXIT
	curl -fL "$url" > "$tmp"
	tar -Oxf "$tmp" "$path" > "$out"
else
	path="cockroach.$os-$arch.$sha"
	url="https://edge-binaries.cockroachdb.com/cockroach/$path"
	if [ os = windows ]; then
		url+=.exe
	fi
	echo "Downloading $url..."
	curl -fL "$url" > "$out"
fi
chmod +x "$out"

