#!/bin/bash

# --- Twit's Env-Variables
export WIT_DEFAULT_SRC WIT_ENV_FORMAT WIT_SETTINGS_FORMAT
WIT_DEFAULT_SRC="${WIT_DEFAULT_SRC:-"${HOME}/.config/twit.json"}"
WIT_ENV_FORMAT='select(.) | to_entries | map("export \(.key)=\"\(.value|tostring)\"") | .[]'
WIT_SETTINGS_FORMAT='select(.) | to_entries | map("export twit_\(.key)=\"\(.value|tostring)\"") | .[]'

# --- Twit's Completions
complete -F _twit_completion twit
complete -F _twit_group_completion twit_group
complete -F _twit_manifest_completion twit_env
complete -F _twit_manifest_completion twit_forget
complete -F _twit_manifest_completion twit_learn
complete -F _twit_manifest_completion twit_manifest

# twit_group, twit register, members
function _twit_debug() {
	echo "${@}" >&2
}

function _twit_settings() {
	eval "$(jq -r ".settings | ${WIT_SETTINGS_FORMAT}" "${WIT_DEFAULT_SRC}")"
	twit_default_directory="$(echo "${twit_default_directory}" | sed "s|^~|${HOME}|")"
}
# Make and CD into a directory
#    dir              : str : Defaults to 'untitled'
function mkent() {
	dir="${1:-untitled}"
	if [ -d "$dir" ]; then
		echo 'Path exists, no creation required' >/dev/null
	else
		mkdir -p "${dir}"
	fi
	cd "${dir}" || {
		echo "Failed to enter directory" >&2
		return 2
	}
}

# --- Twit's Config Management
if ! [[ -s "${WIT_DEFAULT_SRC}" ]]; then
	cat <<EOF | sed 's/,}/}/' | jq '.' >"${WIT_DEFAULT_SRC}"
{"settings": {
    "load_globals": true,
    "parallel_twits": 2,
    "default_reference": "home",
	"default_directory": "~/Git",
	"default_remote": "$(git config remote.origin.url)",
    "default_command": "ls",
	"create_missing_path": true
  	}, "global_env": {},
  	"manifest": {
	$(
		ls -d ${HOME}/*/ |
			rev | cut -f2 -d'/' | rev |
			sed 's|^.*$|"&": {"path": "~/&", "env":{}},|' | tr -d '\n'
	)},
	"groups": {"default": ["home"]}}
EOF
fi

function twit_learn() {
	manifest_reference="${1:-$(pwd | rev | cut -f1 -d/ | rev)}"

	_twit_debug "Twit's Learning about ${manifest_reference} please ammend as needed"
	cleaned_path="$(pwd | sed "s|^@|${twit_default_directory}|" | sed "s|^~|${HOME}|")"
	repo_info="$(git config remote.origin.url)"
	case "${manifest_reference}" in
	\~* | \?*) _twit_debug "For now, no. But later... perhaps." && return 0 ;;
	all) _twit_debug "I'd love to... but no." && return 1 ;;
	*) jq ".manifest+={\"${manifest_reference}\": {\"path\":\"${cleaned_path}\"}}" "${WIT_DEFAULT_SRC}" >"${WIT_DEFAULT_SRC}.bak" ;;
	esac

	if [[ -s "${WIT_DEFAULT_SRC}.bak" ]]; then
		mv "${WIT_DEFAULT_SRC}.bak" "${WIT_DEFAULT_SRC}" && _twit_debug "I learned"
	else
		_twit_debug "I messedup, please check ${WIT_DEFAULT_SRC} and the adjecent .bak file"
	fi

}
function twit_forget() {
	_twit_settings
	if [[ "${1}" == '' ]]; then
		cleaned_path="$(pwd | sed "s|^${HOME}|~|" | sed "s|^${twit_default_directory}|@|")"
		manifest_reference="$(jq -r "path(.manifest[] | select(.path == \"${cleaned_path}\"))[1]" "${WIT_DEFAULT_SRC}")"
	else
		manifest_reference="${1}"
	fi
	_twit_debug "Twit wants to forget (${manifest_reference})"
	if [[ -n "${manifest_reference}" ]]; then
		case "${manifest_reference}" in
		\~* | \?*) jq "del(.groups.\"${manifest_reference:0}\")" "${WIT_DEFAULT_SRC}" ;;
		all) jq ".manifest={}" "${WIT_DEFAULT_SRC}" ;;
		*) jq "del(.manifest.\"${manifest_reference}\")" "${WIT_DEFAULT_SRC}" ;;
		esac >"${WIT_DEFAULT_SRC}.bak"
		if [[ -s "${WIT_DEFAULT_SRC}.bak" ]]; then
			mv "${WIT_DEFAULT_SRC}.bak" "${WIT_DEFAULT_SRC}" && _twit_debug "I forgot."
		else
			_twit_debug "I messedup, please check ${WIT_DEFAULT_SRC} and the adjecent .bak file"
		fi

	else
		_twit_debug "Might want to teach me something first..."
	fi
}

# --- Twit's Group Queries
function _twit_group_completion() {
	local suggestions
	local cur="${COMP_WORDS[COMP_CWORD]}"
	local first_arg="${COMP_WORDS[1]}"
	if [[ "${COMP_CWORD}" -eq 1 ]]; then
		suggestions="$(
			jq -r '.groups | keys[]' "${WIT_DEFAULT_SRC}" | sed 's/^/\?&/'
			jq -r '.groups | keys[]' "${WIT_DEFAULT_SRC}" | sed 's/^/~&/'
		)"
	fi
	COMPREPLY=($(compgen -W "${suggestions}" -- "$cur"))
}
function twit_group() {
	group_reference="${1}"
	[[ "${group_reference}" == '' ]] && return 1
	case "${group_reference}" in
	\~*) twit_group "${group_reference/\~/}" ;;
	\?*) twit_group "${group_reference/\?/}" ;;
	all) jq -r ".manifest | keys[]" "${WIT_DEFAULT_SRC}" ;;
	*) jq -r ".groups.\"${group_reference}\"[]" "${WIT_DEFAULT_SRC}" ;;
	esac
}

# --- Twit's Manifest Queries
function _twit_manifest_completion() {
	local suggestions
	local cur="${COMP_WORDS[COMP_CWORD]}"
	local first_arg="${COMP_WORDS[1]}"
	if [[ "${COMP_CWORD}" -eq 1 ]]; then
		suggestions="$(
			jq -r '.manifest | keys[]' "${WIT_DEFAULT_SRC}"
			jq -r '.groups | keys[]' "${WIT_DEFAULT_SRC}" | sed 's/^/\?&/'
			jq -r '.groups | keys[]' "${WIT_DEFAULT_SRC}" | sed 's/^/~&/'
		)"
	else
		suggestions="$(
			jq -r ".manifest.\"${first_arg}\" | select(.) | keys[]" "${WIT_DEFAULT_SRC}"
		)"
	fi
	COMPREPLY=($(compgen -W "${suggestions}" -- "$cur"))
}
function twit_manifest() {
	_twit_settings
	manifest_reference="${1:-$twit_default_refefence}"
	manifest_element="${2}"
	if [[ "${manifest_reference}" == "keys" ]]; then
		echo "listing known manifests"
		jq -r ".manifest | keys[]" "${WIT_DEFAULT_SRC}"
		return
	fi

	if [[ "${manifest_reference:0:1}" == "@" ]]; then
		jq -r ".groups.\"${manifest_reference/\@/}\"[]" "${WIT_DEFAULT_SRC}" |
			while read -r group_reference; do
				twit_manifest "${group_reference}" "${manifest_element}"
			done
	else
		if ! [[ "${manifest_element}" == "" ]]; then
			if ! [[ "${manifest_element:0:1}" == "." ]]; then
				manifest_element=".${manifest_element}"
			fi
		fi
		case "${manifest_element}" in
		\.path)
			jq -r ".manifest.\"${manifest_reference}\"${manifest_element}" "${WIT_DEFAULT_SRC}" |
				sed "s|^~|${HOME}|" | sed "s|^@|${twit_default_directory}|"
			;;
		\.env)
			echo "# Manifest twit vars (${manifest_reference})"
			jq -r ".manifest.\"${manifest_reference}\"${manifest_element} | ${WIT_ENV_FORMAT}" "${WIT_DEFAULT_SRC}"
			echo "# Manifest's repo information"
			echo "export repo_remote=\"$(twit_manifest "${manifest_reference}" '.remote')\""
			;;
		\.remote)
			jq -r ".manifest.\"${manifest_reference}\".remote | select(.)" "${WIT_DEFAULT_SRC}" |
				sed "s|^@|${twit_default_remote}|"
			;;
		*) jq -r ".manifest.\"${manifest_reference}\"${manifest_element}" "${WIT_DEFAULT_SRC}" ;;
		esac
	fi
}

# --- Twit's env format
function twit_env {
	_twit_settings
	# -- Command arguments
	manifest_reference="${1:-$twit_default_reference}"

	if [[ "${twit_load_globals}" == "true" ]]; then
		echo "# Global twit vars"
		jq -r ".global_env | ${WIT_ENV_FORMAT}" "${WIT_DEFAULT_SRC}"
	fi

	if [[ "${PWD}" == "$(twit_manifest "${manifest_reference}" ".path")"* ]]; then
		twit_manifest "${manifest_reference}" "env"
	fi
}

# --- Twit
function _twit_completion() {
	local suggestions
	local cur="${COMP_WORDS[COMP_CWORD]}"
	local first_arg="${COMP_WORDS[1]}"
	if [[ "${COMP_CWORD}" -eq 1 ]]; then
		suggestions="$(
			jq -r '.manifest | keys[]' "${WIT_DEFAULT_SRC}"
			jq -r '.groups | keys[]' "${WIT_DEFAULT_SRC}" | sed 's/^/\?&/'
			jq -r '.groups | keys[]' "${WIT_DEFAULT_SRC}" | sed 's/^/~&/'
		)"
	else
		suggestions="$(compgen -c)"
	fi
	COMPREPLY=($(compgen -W "${suggestions}" -- "$cur"))
}
function twit() {
	_twit_settings
	manifest_reference="${1:-$twit_default_reference}"
	shift 1

	case "${1}" in
	cd)
		[[ "${manifest_reference:0:1}" == "~" || "${manifest_reference:0:1}" == "?" ]] && return 1
		cd "$(twit_manifest "${manifest_reference}" 'path')" || return 1 && return 0
		;;
	twit) _twit_debug "Don't call yourself... It's unseemly" && return 1 ;;
	*) ;;
	esac
	case "${manifest_reference}" in
	~*)

		twit_group "${manifest_reference/\~/}" |
			while read -r group_reference; do
				if [[ "${group_reference}" == "${manifest_reference}" ]]; then
					_twit_debug "Calling ${group_reference} feels recursive..."
				else

					echo "twit ${group_reference} ${@}"
				fi
			done | parallel \
			--max-procs "${twit_parallel_twits:-1}" \
			--group --keep-order --color \
			--env WIT_DEFAULT_SRC \
			--env WIT_SETTINGS_FORMAT \
			--env WIT_ENV_FORMAT
		;;
	\?*)
		twit_group "${manifest_reference/\?/}" |
			while read -r group_reference; do
				if [[ "${group_reference}" == "${manifest_reference}" ]]; then
					_twit_debug "Calling ${group_reference} feels recursive..."
				else
					_twit_debug "# Running in ${group_reference}; "
					twit "${group_reference}" $@
				fi
			done
		;;
	*)
		manifest_path_var="$(
			jq -r ".manifest[\"${manifest_reference}\"].path | select(.)" "${WIT_DEFAULT_SRC}" |
				sed "s@^~@${HOME}@"
		)"
		[[ "${manifest_path_var}" == '' ]] && {
			_twit_debug "Path not set. Breaking down now."
			return 1
		}
		manifest_path="$(realpath -m "${manifest_path_var}")"
		if [[ -n "${manifest_path}" ]]; then
			(
				cd "${manifest_path}" || if [[ "${twit_create_missing_path}" == "true" ]]; then
					_twit_debug "Creating path first."
					mkent "${manifest_path}" || return 0
				else
					_twit_debug "Location may not exist, please set twit_create_missing_path [${twit_create_missing_path}]"
					return 0
				fi

				if (compgen -c twit_ | grep -q "^twit_${1:-$twit_default_command}\$"); then # prepend twit for twit-specific commands
					command="twit_${1:-$twit_default_command}"
				else
					command="${1}"
				fi
				shift 1
				eval "
$(twit_env "${manifest_reference}")
${command:-$twit_default_command} ${@} "
			)
		else
			_twit_debug "Something went wrong, might need to check yourself as you maybe wrecked yourself."
		fi
		;;
	esac

}

# --- Twit's function export
export -f mkent twit twit_group twit_manifest twit_env _twit_debug _twit_settings
