fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'norte_bancada_props'
description 'O prop nr_bancada_municoes da norte_bancada. Só assets: não se reinicia com o jogo a correr.'
version '1.0.0'

-- Separado do código: reiniciar um recurso com stream descarrega o modelo, e o jogo de quem tem a máquina
-- criada no mundo rebenta. Assim o norte_bancada reinicia à vontade e o modelo fica carregado.
data_file 'DLC_ITYP_REQUEST' 'stream/nr_bancada.ytyp'
