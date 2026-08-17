#!/bin/bash

matches=$(grep -rnE '\bio\.|os\.(getenv|execute|remove|rename|exit|tmpname)|love\.(filesystem|thread|system|event)|require\("(io|os|debug|package|ffi|love\.)' . | grep -v '^./field/tests/')
if [ -n "$matches" ]; then
    echo "$matches"
    echo "ERROR: Forbidden API usage detected other than in ./field/tests/" >&2
    exit 1
fi
