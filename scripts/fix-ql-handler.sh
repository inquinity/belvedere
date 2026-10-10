#! /bin/zsh
pluginkit -a /Applications/Belvedere.app/Contents/PlugIns/belvedere-quick-look.appex
pluginkit -e use -i com.altmansoftwaredesign.belvedere.quick-look
qlmanage -r
qlmanage -r cache
