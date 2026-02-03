#!/bin/bash
# Wrapper for ar that handles long command lines on Windows
# MinGW ar doesn't support @file syntax, so we expand them
# Also handles the case where the command line is too long

REAL_AR="/c/Users/Preston/.choosenim/toolchains/mingw64/bin/ar.exe"

# Build new argument list, expanding @file references
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == @* ]]; then
        # This is a response file - read its contents
        respfile="${arg:1}"
        # Handle /dev/null specially (empty input)
        if [[ "$respfile" == "/dev/null" ]]; then
            # No files to add
            :
        elif [[ -e "$respfile" ]]; then
            # Read file and split by whitespace (files may be space or newline separated)
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Strip carriage returns (Windows line endings)
                line="${line%$'\r'}"
                # Skip empty lines
                [[ -z "$line" ]] && continue
                # Split by spaces and add each file
                for file in $line; do
                    [[ -n "$file" ]] && ARGS+=("$file")
                done
            done < "$respfile"
        else
            echo "ar-wrapper: Response file not found: $respfile" >&2
            exit 1
        fi
    else
        ARGS+=("$arg")
    fi
done

# If the number of args is large, call ar in batches
if [[ ${#ARGS[@]} -gt 200 ]]; then
    # Extract flags and output file
    ARFLAGS="${ARGS[0]}"
    OUTPUT="${ARGS[1]}"

    # Remove existing archive to start fresh
    rm -f "$OUTPUT"

    # Add all files in batches
    batch_size=50
    i=2
    while [[ $i -lt ${#ARGS[@]} ]]; do
        batch=("${ARGS[@]:$i:$batch_size}")
        # Use 'q' (quick append) for speed, then index at the end
        "$REAL_AR" q "$OUTPUT" "${batch[@]}"
        ((i += batch_size))
    done
    # Update the index
    "$REAL_AR" s "$OUTPUT"
else
    exec "$REAL_AR" "${ARGS[@]}"
fi
