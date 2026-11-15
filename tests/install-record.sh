#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
# Reordered fields prove reads/writes use names, not the historical URL column.
# Used by the sourced record accessors.
# shellcheck disable=SC2034
install_field_names='source_url id action state schema_version'
record='old|sample|install||2'
updated="$(install_record_update "$record" source_url 'https://example.test/a?key=x=y' state 'literal\path' action skip)"
[[ "$updated" == 'https://example.test/a?key=x=y|sample|skip|literal\path|2' ]]
[[ "$(install_field "$updated" id)" == sample ]]
if install_record_update "$record" absent value >/dev/null;then exit 1;fi
if install_record_update "$record" id first id second >/dev/null;then exit 1;fi
if install_record_update "$record" id $'bad\nvalue' >/dev/null;then exit 1;fi
if install_record_update "$record" id 'bad|value' >/dev/null;then exit 1;fi
# Generated fields are not user declaration fields.
if awk -F '\t' '$1=="discovery" {found=1} END {exit !found}' "$repo_root/install/schema/fields.tsv";then exit 1;fi
printf 'Named install record reads/updates, literal values and declaration separation passed.\n'
