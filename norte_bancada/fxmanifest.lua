fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'norte_bancada'
description 'Máquina de carregar carregadores: item colocável que carrega os carregadores do whip_gunny sozinha'
version '1.0.0'

dependencies {
    'whip_core',
    'norte_bancada_props',       -- o modelo da máquina, num recurso à parte (ver o fxmanifest de lá)
    'norte_bancada_mk2_props',   -- o modelo da MK2, também à parte
}
whip_requires '1.0'

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'settings.lua',   -- a página em /whip → Settings (Whip.configPage)
}

server_script 'server.lua'

client_scripts {
    'encaixe.lua',       -- export getApoio, da versão original do prop
    'encaixe_mk2.lua',   -- export getApoioMk2, do pacote da MK2
    'client.lua',
}

-- Sem nada visível: só toca o som do motor. O progresso está no ecrã do modelo (html/screen.html, DUI).
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/tokens.css',
    'html/script.js',
    'html/screen.html',   -- o ecrã das máquinas (DUI)
    'html/screen.css',
    'html/screen.js',
    'html/sounds/motor_bancada_loop.wav',   -- o motor da máquina a trabalhar
    -- Ícone do item: o whip_core procura-o neste recurso, com o nome do item.
    'html/img/items/*.png',   -- norte_bancada.png e norte_bancada_mk2.png
}
