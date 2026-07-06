#!/bin/bash

set -euo pipefail

archive_path="${1:?Usage: backup_archive_to_github.sh ARCHIVE_PATH RELEASE_ASSETS_DIR}"
release_assets_dir="${2:?Usage: backup_archive_to_github.sh ARCHIVE_PATH RELEASE_ASSETS_DIR}"

fail() {
	printf "Archive backup failed: %s\n" "$1" >&2
	exit 1
}

for tool in gh git ditto shasum stat; do
	command -v "$tool" >/dev/null || fail "Missing required tool: $tool"
done

repo_root="$(git rev-parse --show-toplevel)"
archive_dir="$repo_root/build/Archives"
mkdir -p "$archive_dir" "$release_assets_dir"

archive_parent="$(cd "$(dirname "$archive_path")" && pwd -P)"
[[ "$archive_parent" == "$archive_dir" ]] || fail "Refusing to manage an archive outside $archive_dir"
[[ "$archive_path" == *.xcarchive ]] || fail "Archive path must end in .xcarchive"
[[ -d "$archive_path" ]] || fail "Missing archive at $archive_path"

archive_info="$archive_path/Info.plist"
[[ -f "$archive_info" ]] || fail "Missing archive Info.plist"

version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive_info")"
build="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive_info")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$archive_info")"
tag="testflight-$version-$build"
archive_name="Clinical-$version-$build.xcarchive.zip"
zip_path="$release_assets_dir/$archive_name"
checksum_path="$zip_path.sha256"
head_commit="$(git rev-parse HEAD)"

repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
visibility="$(gh repo view --json visibility --jq '.visibility')"
[[ "$visibility" == "PRIVATE" ]] || fail "Archive releases require a private repository; $repo is $visibility"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
	local_tag_commit="$(git rev-list -n 1 "$tag")"
	[[ "$local_tag_commit" == "$head_commit" ]] || fail "Local tag $tag points to $local_tag_commit instead of $head_commit"
else
	git tag -a "$tag" "$head_commit" -m "Clinical $version ($build) TestFlight archive"
fi

remote_tag_commit="$(git ls-remote --tags origin "refs/tags/$tag^{}" | awk 'NR == 1 { print $1 }')"
if [[ -z "$remote_tag_commit" ]]; then
	remote_tag_commit="$(git ls-remote --tags origin "refs/tags/$tag" | awk 'NR == 1 { print $1 }')"
fi

if [[ -n "$remote_tag_commit" ]]; then
	[[ "$remote_tag_commit" == "$head_commit" ]] || fail "Remote tag $tag points to $remote_tag_commit instead of $head_commit"
else
	git push origin "refs/tags/$tag"
fi

if [[ -f "$zip_path" && -f "$checksum_path" ]] && (cd "$release_assets_dir" && shasum -a 256 -c "$(basename "$checksum_path")" >/dev/null); then
	printf "Using existing verified archive ZIP: %s\n" "$zip_path"
else
	rm -f "$zip_path" "$checksum_path"
	printf "Compressing %s...\n" "$archive_path"
	ditto -c -k --sequesterRsrc --keepParent "$archive_path" "$zip_path"
	zip_hash="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"
	printf "%s  %s\n" "$zip_hash" "$archive_name" > "$checksum_path"
fi

zip_hash="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"

if [[ -n "$(git status --porcelain)" ]]; then
	provenance_note="This archive was created from a working tree containing uncommitted changes. The tag identifies the nearest committed base rather than the archive's exact source state."
else
	provenance_note="The release tag identifies the source commit used to create this archive."
fi

if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
	gh release create "$tag" \
		--repo "$repo" \
		--verify-tag \
		--draft \
		--prerelease \
		--latest=false \
		--title "Clinical $version ($build) TestFlight Archive" \
		--notes "Private archive backup for Clinical $version ($build).

Bundle ID: $bundle_id
Source commit: $head_commit
Archive SHA-256: $zip_hash

$provenance_note"
fi

verify_asset() {
	local asset_path="$1"
	local asset_name expected_size expected_digest remote_metadata remote_size remote_digest

	asset_name="$(basename "$asset_path")"
	expected_size="$(stat -f '%z' "$asset_path")"
	expected_digest="sha256:$(shasum -a 256 "$asset_path" | awk '{ print $1 }')"
	remote_metadata="$(gh release view "$tag" --repo "$repo" --json assets --jq ".assets[] | select(.name == \"$asset_name\") | [(.size | tostring), .digest] | @tsv")"
	[[ -n "$remote_metadata" ]] || return 1

	IFS=$'\t' read -r remote_size remote_digest <<< "$remote_metadata"
	[[ "$remote_size" == "$expected_size" && "$remote_digest" == "$expected_digest" ]]
}

upload_asset() {
	local asset_path="$1"
	local asset_name

	asset_name="$(basename "$asset_path")"
	if gh release view "$tag" --repo "$repo" --json assets --jq ".assets[].name" | grep -Fxq "$asset_name"; then
		verify_asset "$asset_path" || fail "Existing GitHub asset does not match $asset_name"
		printf "Verified existing GitHub asset: %s\n" "$asset_name"
		return
	fi

	printf "Uploading GitHub asset: %s\n" "$asset_name"
	gh release upload "$tag" "$asset_path" --repo "$repo"
	verify_asset "$asset_path" || fail "GitHub asset verification failed for $asset_name"
}

upload_asset "$zip_path"
upload_asset "$checksum_path"

is_draft="$(gh release view "$tag" --repo "$repo" --json isDraft --jq '.isDraft')"
if [[ "$is_draft" == "true" ]]; then
	gh release edit "$tag" --repo "$repo" --draft=false --prerelease --latest=false >/dev/null
fi

release_url="$(gh release view "$tag" --repo "$repo" --json isDraft,isPrerelease,url --jq 'select(.isDraft == false and .isPrerelease == true) | .url')"
[[ -n "$release_url" ]] || fail "GitHub release was not published as a prerelease"

rm -f "$zip_path" "$checksum_path"

printf "Archive backed up and verified: %s\n" "$release_url"
