Config = {}

-- Os tipos de máquina, um item cada. A chave é o item do inventário (e o nome do ícone em html/img/items).
--   model         o prop (origem no centro da base, ao nível dos pés), em norte_bancada_props / norte_bancada_mk2_props
--   layout        como encaixar a caixa e os carregadores: 'single' (encaixe.lua, os carregadores lado a lado no y)
--                 ou 'mk2' (encaixe_mk2.lua, 4 apoios com 3 lugares cada)
--   maxMags       carregadores que cabem de cada vez (também em /whip → Settings → Magazine Loader)
--   shown         carregadores desenhados na máquina
--   slots, maxWeight   o contentor do WHIP por trás (trancado: só este recurso lhe mexe)
--   magSlots, perSlot  opcional: os carregadores escolhem-se por slot (magSlots slots de perSlot carregadores)
--   promptPlaced  true: o prompt fica no promptPoint, e o PromptSide / PromptHeight / PromptGap não contam (o PromptScale sim)
--   promptPoint   x, y, z no referencial do prop e w o heading a partir do da máquina (180 = virado para trás).
--                 Mede-se com /int <modelo> (norte_int) e escreve-se aqui ou em /whip → Settings → Magazine Loader
--   promptPoints  opcional, { ammo, mags, machine }: com promptPlaced, três prompts separados (balas, carregadores,
--                 ligar e guardar), cada um no seu ponto. Sem ele, um prompt só no promptPoint
Config.Types = {
    norte_bancada = {
        label = 'Magazine Loader', weight = 4.0,
        desc = 'Loads up to 3 magazines by itself. Use it to place it on the ground or a bench.',
        model = 'nr_bancada_municoes', layout = 'single',
        maxMags = 3, shown = 3, slots = 24, maxWeight = 40.0,
        -- Um prompt com todas as opções, no ponto tirado com /int (norte_int), no referencial do prop.
        promptPlaced  = true,
        promptPoint   = vector4(0.023, -0.177, 0.227, 180.0),
        -- O ecrã do modelo: a textura nr_mk1_ecra (do .ytd nr_bancada) passa a ser a página html/screen.html.
        screen = { txd = 'nr_bancada', texture = 'nr_mk1_ecra', width = 640, height = 360, title = 'NR-MK1 · MAGAZINE LOADER' },
    },
    norte_bancada_mk2 = {
        label = 'Magazine Loader MK2', weight = 9.0,
        desc = 'Loads up to 12 magazines by itself. Use it to place it on the ground or a bench.',
        model = 'nr_bancada_mk2_municoes', layout = 'mk2',
        maxMags = 12, shown = 12, slots = 30, maxWeight = 80.0,
        -- Um prompt com todas as opções, no ponto tirado com /int (norte_int), no referencial do prop.
        promptPlaced  = true,
        promptPoint   = vector4(-0.454, -0.233, 0.203, 180.0),
        -- Os carregadores vão por slots: 4 apoios com 3 lugares cada. No prompt, "Magazine slots" → Slot 1 a 4.
        -- No contentor, o slot g são os lugares (g-1)*3+1 a g*3, e as balas vão do 13 para a frente.
        magSlots = 4, perSlot = 3,
        -- O ecrã do modelo: a textura nr_mk2_ecra (do .ytd nr_bancada_mk2) passa a ser a página html/screen.html.
        screen = { txd = 'nr_bancada_mk2', texture = 'nr_mk2_ecra', width = 640, height = 360, title = 'NR-MK2 · MAGAZINE LOADER' },
    },
}
Config.DefaultType = 'norte_bancada'   -- máquinas guardadas antes de haver tipos

--- O tipo de uma máquina (ou do nome de um tipo); um desconhecido é o de origem.
function Config.TypeOf(kind)
    return Config.Types[kind] or Config.Types[Config.DefaultType]
end

-- Velocidade: a máquina mete uma bala a cada MsPerRound. O servidor trabalha em passos de TickMs.
-- À mão, o whip_gunny mete uma bala a cada 300 ms.
Config.MsPerRound = 150
Config.TickMs     = 1500

Config.PlaceRange   = 6.0    -- metros entre o jogador e o sítio onde a coloca
Config.MinSpacing   = 1.2    -- metros entre duas máquinas

-- O colocador (client.lua): a máquina só fica onde a caixa do modelo não toca em muros, carros nem objetos.
Config.PlaceReach      = 5.0    -- metros à frente do jogador onde o fantasma pode ir
Config.PlaceFlat       = 0.85   -- quão plana a superfície tem de ser (1.0 = horizontal)
Config.PlaceShrink     = 0.92   -- a caixa testada é 8% menor que o modelo, para os bordos não contarem
Config.PlaceLift       = 0.04   -- metros acima do chão onde a caixa começa, para o chão não contar
Config.PlaceRotateStep = 10.0   -- graus por passo do scroll
Config.UseRange     = 2.5    -- metros: o servidor recusa pedidos de mais longe
Config.Reach        = 1.8    -- metros: onde o prompt deixa carregar em E

-- O prompt: colado a um lado da máquina, de pé como uma placa, como os das portas dos carros.
-- Tudo isto também se muda em jogo: /whip → Settings → Magazine Loader → Prompt (vale logo).
Config.PromptSide   = 'back'   -- 'right', 'left', 'front' ou 'back' (do ponto de vista do prop; 'right' é o lado do carregador)
Config.PromptGap    = 0.02     -- metros entre a face da máquina e o prompt
Config.PromptHeight = 0.55     -- altura no lado: 0 é a base, 1 é o topo
Config.PromptScale  = 0.6      -- tamanho do prompt (1 é o tamanho normal do WHIP)

-- Pontos no referencial do prop (x direita, y frente, z cima). Point só se usa se o modelo não carregar.
Config.Point         = vector3(0.0, 0.0, 0.70)
Config.DrawRange     = 80.0  -- metros até onde o cliente cria o prop, a caixa e o carregador

-- O som do motor da máquina a trabalhar (html/sounds/motor_bancada_loop.wav), em loop, com fade in e fade out.
Config.SoundRange  = 12.0    -- metros até onde se ouve
Config.SoundVolume = 0.5     -- volume encostado à máquina (0 a 1); desce com a distância
Config.SoundFadeIn  = 1200    -- ms do silêncio ao volume, quando a máquina começa
Config.SoundFadeOut = 1500    -- ms do volume ao silêncio, quando a máquina pára

Config.MagGap = 0.006        -- metros entre dois carregadores desenhados lado a lado (layout 'single')

-- MsPerRound, o máximo de carregadores de cada tipo e o som também se mudam em /whip → Settings → Magazine Loader.

-- A animação de pôr balas ou carregadores na máquina (barra do servidor, com o objeto na mão).
Config.PutMs   = 2200
Config.PutAnim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 49 }

-- Onde a caixa e o carregador aparecem encaixados, quando o export getApoio (encaixe.lua) não consegue calcular.
-- Vem do apoios.lua da versão original do prop (AttachEntityToEntity, rotationOrder 2).
Config.Apoios = {
    ['whip_ammobox_22lr']       = { pos = vector3(-0.16500, 0.00000, 0.44830), rot = vector3(180, 0, 0) },
    ['whip_ammobox_357']        = { pos = vector3(-0.16500, 0.00000, 0.47079), rot = vector3(180, 0, 0) },
    ['whip_ammobox_36navy']     = { pos = vector3(-0.16500, 0.00000, 0.43675), rot = vector3(180, 0, 0) },
    ['whip_ammobox_44mag']      = { pos = vector3(-0.16500, 0.00000, 0.47154), rot = vector3(180, 0, 0) },
    ['whip_ammobox_45acp']      = { pos = vector3(-0.16500, 0.00000, 0.45655), rot = vector3(180, 0, 0) },
    ['whip_ammobox_50ae']       = { pos = vector3(-0.16500, 0.00000, 0.47020), rot = vector3(180, 0, 0) },
    ['whip_ammobox_50bmg']      = { pos = vector3(-0.16500, 0.00000, 0.61780), rot = vector3(180, 0, 0) },
    ['whip_ammobox_556']        = { pos = vector3(-0.16500, 0.00000, 0.49630), rot = vector3(180, 0, 0) },
    ['whip_ammobox_762x39']     = { pos = vector3(-0.16500, 0.00000, 0.49420), rot = vector3(180, 0, 0) },
    ['whip_ammobox_762x51']     = { pos = vector3(-0.16500, 0.00000, 0.51670), rot = vector3(180, 0, 0) },
    ['whip_ammobox_9mm']        = { pos = vector3(-0.16500, 0.00000, 0.45474), rot = vector3(180, 0, 0) },
    ['whip_ammobox_energycell'] = { pos = vector3(-0.16500, 0.00000, 0.51520), rot = vector3(180, 0, 0) },
    ['whip_ammobox_musket']     = { pos = vector3(-0.16500, 0.00000, 0.53020), rot = vector3(180, 0, 0) },
    ['whip_ammobox_railgun']    = { pos = vector3(-0.16500, 0.00000, 0.52630), rot = vector3(180, 0, 0) },
    ['whip_ammobox_taser']      = { pos = vector3(-0.16500, 0.00000, 0.46720), rot = vector3(180, 0, 0) },
    ['w_ar_whip_assaultrifle_mag1'] = { pos = vector3(0.25420, 0.00000, 0.31805), rot = vector3(0, 0, 0) },
    ['w_ar_whip_assaultrifle_mag2'] = { pos = vector3(0.25200, -0.02539, 0.31805), rot = vector3(0, 0, 90) },
    ['w_pi_whip_heavypistol_mag1']  = { pos = vector3(0.26689, 0.00024, 0.31072), rot = vector3(0, 0, 0) },
    ['w_pi_whip_heavypistol_mag2']  = { pos = vector3(0.27763, 0.00024, 0.31072), rot = vector3(0, 0, 0) },
    ['w_pi_whip_wep2_gun_mag1']     = { pos = vector3(0.27894, -0.00002, 0.29579), rot = vector3(0, 0, 0) },
}
