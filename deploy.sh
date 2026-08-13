#!/bin/bash

rm -rf *.zip
./build.sh && unzip -qo anime_realism-*.zip -d "$HOME/Library/Application Support/pokemon-love2d/mods/anime_realism"
