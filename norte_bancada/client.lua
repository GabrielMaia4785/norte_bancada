-- norte_bancada — cliente
--
-- Um prompt por máquina, com as opções que fazem sentido no momento (canInteract lê o estado que o servidor manda):
--   sem carregadores: Colocar carregadores ›      com carregadores: Retirar carregadores
--   sem balas:        Colocar balas ›             com balas:        Retirar balas
--   com os dois, parada: Iniciar                  sempre, para o dono: Guardar máquina
-- O prop, a caixa e o carregador são objetos locais deste cliente, encaixados com o getApoio (encaixe.lua).
-- Enquanto a máquina trabalha, o ecrã do modelo (DUI, html/screen.html) mostra o progresso.

local Machines = {}   -- [id] = { id, owner, coords, h, state, obj, box, mag, boxModel, magModel }
local placing = false

local ICONS = 'https://cfx-nui-whip_gunny/html/img/items/%s.webp'

--- Um ponto do referencial do prop no mundo: roda o offset pelo heading da máquina.
local function worldPoint(m, off)
    local r = math.rad(m.h or 0.0)
    local c, s = math.cos(r), math.sin(r)
    return m.coords + vector3(off.x * c - off.y * s, off.x * s + off.y * c, off.z)
end

-- ===================================================================================================
-- Objetos: a máquina, a caixa e o carregador
-- ===================================================================================================

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local giveUp = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > giveUp then return nil end
        Wait(0)
    end
    return hash
end

local function deleteObj(obj)
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
end

--- A caixa (posto 'caixa') ou o carregador (posto 'carregador') encaixado na máquina, ou nada.
local function setPart(m, field, model, posto)
    local modelField = field .. 'Model'
    if m[modelField] == model and (model == nil or (m[field] and DoesEntityExist(m[field]))) then return end
    deleteObj(m[field])
    m[field], m[modelField] = nil, model
    if not model or not m.obj then return end

    local hash = loadModel(model)
    if not hash or not m.obj or not DoesEntityExist(m.obj) or m[modelField] ~= model then return end
    local apoio
    if Config.TypeOf(m.kind).layout == 'mk2' then
        apoio = exports.norte_bancada:getApoioMk2(hash, posto)
    else
        apoio = exports.norte_bancada:getApoio(hash, posto) or Config.Apoios[model]
    end
    if not apoio then
        SetModelAsNoLongerNeeded(hash)
        return
    end
    local obj = CreateObjectNoOffset(hash, m.coords.x, m.coords.y, m.coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(obj, false, false)
    local p, r = apoio.pos, apoio.rot
    AttachEntityToEntity(obj, m.obj, -1, p.x, p.y, p.z, r.x, r.y, r.z, false, false, false, false, 2, true)
    m[field] = obj
end

-- Onde vai cada carregador, em passos ao longo do y da máquina: o 1.º no sítio de sempre, o 2.º ao lado, o 3.º
-- do outro lado. A partir do 4.º, segue a alternar.
local function slotStep(i)
    if i == 1 then return 0 end
    local n = math.floor(i / 2)
    return (i % 2 == 0) and n or -n
end

local function clearMags(m)
    for _, obj in ipairs(m.magObjs or {}) do deleteObj(obj) end
    m.magObjs = {}
end

-- Máquina com slots: o lugar l (1 a perSlot) de um slot do contentor vai para este lugar do apoio (encaixe_mk2.lua).
-- O primeiro carregador de um slot fica no meio.
local LUGAR_OF = { 2, 1, 3 }

--- Máquina com slots (MK2): um carregador em cada lugar do contentor que tem um (state.magPos), no apoio do seu slot.
local function setMagsSlotted(m, magPos)
    local T = Config.TypeOf(m.kind)
    local parts = {}
    for p = 1, T.magSlots * T.perSlot do parts[p] = magPos[p] or '-' end
    local key = table.concat(parts, ',')
    local alive = m.magObjs ~= nil
    for _, obj in ipairs(m.magObjs or {}) do
        if not DoesEntityExist(obj) then alive = false end
    end
    if m.magKey == key and alive then return end
    clearMags(m)
    m.magKey = key
    if not m.obj then return end

    for p, model in ipairs(parts) do
        if model ~= '-' then
            local hash = loadModel(model)
            if m.magKey ~= key or not m.obj or not DoesEntityExist(m.obj) then return end
            if hash then
                local g = math.ceil(p / T.perSlot)
                local l = (p - 1) % T.perSlot + 1
                local apoio = exports.norte_bancada:getApoioMk2(hash, 'carregador', g, LUGAR_OF[l] or l)
                if apoio then
                    local obj = CreateObjectNoOffset(hash, m.coords.x, m.coords.y, m.coords.z, false, false, false)
                    SetEntityCollision(obj, false, false)
                    local pos, r = apoio.pos, apoio.rot
                    AttachEntityToEntity(obj, m.obj, -1, pos.x, pos.y, pos.z, r.x, r.y, r.z, false, false, false, false, 2, true)
                    m.magObjs[#m.magObjs + 1] = obj
                end
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end
end

--- Os carregadores encaixados na máquina, um por carregador lá dentro (até o `shown` do tipo).
local function setMags(m, model, count)
    local T = Config.TypeOf(m.kind)
    count = math.min(count or 0, T.shown)
    if not model then count = 0 end
    local objs = m.magObjs or {}
    local alive = #objs == m.magCount
    for _, obj in ipairs(objs) do
        if not DoesEntityExist(obj) then alive = false end
    end
    if m.magModel == model and m.magCount == count and alive then return end
    clearMags(m)
    m.magModel, m.magCount = model, count
    if count < 1 or not m.obj then return end

    local hash = loadModel(model)
    if not hash or not m.obj or not DoesEntityExist(m.obj) or m.magModel ~= model or m.magCount ~= count then return end
    local apoio = exports.norte_bancada:getApoio(hash, 'carregador') or Config.Apoios[model]
    if not apoio then
        SetModelAsNoLongerNeeded(hash)
        return
    end

    -- A grossura do carregador ao longo do y da máquina: com rot z = 90 é o x do modelo, senão o y.
    local dmin, dmax = GetModelDimensions(hash)
    local turned = math.abs(apoio.rot.z % 180.0 - 90.0) < 1.0
    local thick = turned and (dmax.x - dmin.x) or (dmax.y - dmin.y)
    local step = thick + Config.MagGap

    local p, r = apoio.pos, apoio.rot
    for i = 1, count do
        local obj = CreateObjectNoOffset(hash, m.coords.x, m.coords.y, m.coords.z, false, false, false)
        SetEntityCollision(obj, false, false)
        AttachEntityToEntity(obj, m.obj, -1, p.x, p.y + slotStep(i) * step, p.z, r.x, r.y, r.z,
            false, false, false, false, 2, true)
        m.magObjs[#m.magObjs + 1] = obj
    end
    SetModelAsNoLongerNeeded(hash)
end

local function syncParts(m)
    local s = m.state or {}
    setPart(m, 'box', s.boxProp, 'caixa')
    if Config.TypeOf(m.kind).magSlots then
        setMagsSlotted(m, type(s.magPos) == 'table' and s.magPos or {})
    else
        setMags(m, s.magProp, s.mags)
    end
end

local function spawn(m)
    if m.obj or m.spawning then return end
    m.spawning = true
    local hash = loadModel(Config.TypeOf(m.kind).model)
    if hash and Machines[m.id] == m then
        local obj = CreateObjectNoOffset(hash, m.coords.x, m.coords.y, m.coords.z, false, false, false)
        SetEntityHeading(obj, m.h or 0.0)
        FreezeEntityPosition(obj, true)
        m.obj = obj
        syncParts(m)
    end
    if hash then SetModelAsNoLongerNeeded(hash) end
    m.spawning = false
end

local function despawn(m)
    deleteObj(m.box)
    clearMags(m)
    deleteObj(m.obj)
    m.obj, m.box, m.boxModel, m.magModel, m.magCount, m.magKey = nil, nil, nil, nil, nil, nil
end

-- ===================================================================================================
-- O prompt
-- ===================================================================================================

-- A quantidade: uma linha "< 0 / 100 rounds >" que as setas esquerda e direita mudam, e E confirma.
-- O WHIP pergunta o label a cada frame enquanto a linha está à vista: é isso que liga as setas (Stepper.seen).
local Stepper = { cur = nil, seen = 0 }
local KEY_LEFT, KEY_RIGHT = 174, 175   -- INPUT_CELLPHONE_LEFT / RIGHT: as setas do teclado, o d-pad no comando

local function stepperRow(id, side, item, max, slot)
    local st = { n = 0, max = max }
    return {
        id = 'amount',
        label = function()
            Stepper.cur, Stepper.seen = st, GetGameTimer()
            local unit = side == 'ammo' and 'rounds' or (st.max == 1 and 'magazine' or 'magazines')
            return ('<  %d / %d %s  >'):format(st.n, st.max, unit)
        end,
        onSelect = function(ctx)
            if st.n < 1 then
                ctx.refuse('Choose how many with the left and right arrows')
                return
            end
            TriggerServerEvent('norte_bancada:put', id, side, item, st.n, slot or 0)
        end,
    }
end

-- As setas, só enquanto a linha da quantidade está à vista. Carregar muda 1; segurar repete, e nas balas
-- acelera para 5 e 10 de cada vez. Para a esquerda no 0 salta para o máximo.
CreateThread(function()
    local held
    while true do
        local st = Stepper.cur
        if st and GetGameTimer() - Stepper.seen < 250 then
            DisableControlAction(0, KEY_LEFT, true)
            DisableControlAction(0, KEY_RIGHT, true)
            local dir = IsDisabledControlPressed(0, KEY_RIGHT) and 1 or IsDisabledControlPressed(0, KEY_LEFT) and -1 or 0
            local now = GetGameTimer()
            if dir == 0 then
                held = nil
            elseif not held or held.dir ~= dir then
                held = { dir = dir, since = now, next = now + 350 }
                if dir < 0 and st.n == 0 then st.n = st.max
                elseif dir > 0 and st.n == st.max then st.n = 0
                else st.n = st.n + dir end
            elseif now >= held.next then
                local t = now - held.since
                local step = st.max <= 12 and 1 or t > 2500 and 10 or t > 1200 and 5 or 1
                st.n = math.max(0, math.min(st.max, st.n + dir * step))
                held.next = now + 70
            end
            Wait(0)
        else
            Stepper.cur, held = nil, nil
            Wait(200)
        end
    end
end)

--- Uma linha que só explica: escolhê-la diz porquê no prompt.
local function infoRow(id, label, why)
    return { id = id, label = label, onSelect = function(ctx) ctx.refuse(why or label) end }
end

--- A lista para "Colocar": um tipo por linha, com imagem. Escolher abre a quantidade, que se muda com as setas.
--- (A quantidade escrita no prompt, ctx.beginInput, falha no whip_core deste servidor: PromptTyping a nil.)
--- slot: numa máquina com slots (MK2), o slot onde vão os carregadores.
local function pocketOptions(id, side, slot)
    local list, why = Whip.core:Callback('norte_bancada:pockets', id, side)
    if type(list) ~= 'table' then
        return { infoRow('erro', 'Could not read your inventory', why) }
    end
    local out = {}
    for _, e in ipairs(list) do
        local item, count, total = e.item, tonumber(e.count) or 0, tonumber(e.total) or 0
        local row = { id = item, image = ICONS:format(item) }
        if side == 'ammo' then
            row.label = ('%s · %d'):format(e.label, count)
        elseif count < 1 then
            row.label = ('%s · %d full'):format(e.label, total)
        else
            row.label = ('%s · %d to fill'):format(e.label, count)
        end

        if count < 1 then
            row.onSelect = function(ctx) ctx.refuse('Those magazines are already full') end
        else
            -- Carregadores: no máximo o maxMags do tipo da máquina, ou o perSlot num slot (o servidor corta o
            -- que já lá estiver).
            local max = count
            if side ~= 'ammo' then
                local T = Config.TypeOf(Machines[id] and Machines[id].kind)
                max = math.min(count, slot and T.perSlot or T.maxMags)
            end
            -- Uma função: cada vez que se abre, a quantidade começa no 0.
            row.options = function() return { stepperRow(id, side, item, max, slot) } end
        end
        out[#out + 1] = row
    end
    if #out == 0 then
        out[1] = infoRow('vazio', side == 'ammo' and 'You have no rounds' or 'You have no magazines')
    end
    return out
end

-- Os lados da máquina, no referencial do prop: a normal que aponta para fora (o +y é a frente no GTA).
local SIDES = {
    right = vector3(1.0, 0.0, 0.0), left = vector3(-1.0, 0.0, 0.0),
    front = vector3(0.0, 1.0, 0.0), back = vector3(0.0, -1.0, 0.0),
}

--- Onde fica o prompt: colado a um lado da máquina, de pé como uma placa virada para fora, como os das portas dos
--- carros. Lê as medidas do modelo (GetModelDimensions). Devolve as coordenadas e o heading do prompt.
local function sidePrompt(m, hash)
    local dmin, dmax = GetModelDimensions(hash)
    local n = SIDES[Config.PromptSide] or SIDES.right
    local centre = (dmin + dmax) * 0.5
    local gap = Config.PromptGap
    local local_ = vector3(
        n.x > 0 and dmax.x + gap or n.x < 0 and dmin.x - gap or centre.x,
        n.y > 0 and dmax.y + gap or n.y < 0 and dmin.y - gap or centre.y,
        dmin.z + (dmax.z - dmin.z) * Config.PromptHeight)
    local coords = worldPoint(m, local_)
    -- A normal no mundo, e o heading do GTA para ela (a mesma conta que o whip_core usa nos contentores).
    local w = worldPoint({ coords = vector3(0.0, 0.0, 0.0), h = m.h }, n)
    local heading = math.deg(math.atan(-w.x, w.y)) % 360.0
    return coords, heading
end

local addActionAt   -- (abaixo)

-- Os prompts separados (promptPoints): cada um mostra só as suas opções.
local PARTS = { 'ammo', 'mags', 'machine' }
local PART_OPTIONS = {
    ammo = { ammo_add = true, ammo_take = true },
    mags = { mag_add = true, mag_take = true, slots = true },
    machine = { start = true, stop = true, store = true },
}

--- MK2: o menu "Magazine slots", Slot 1 a magSlots. Um slot vazio abre os carregadores do inventário; um com
--- carregadores abre "Remove magazines".
local function slotRows(m)
    local T = Config.TypeOf(m.kind)
    local s = m.state or {}
    local rows = {}
    for g = 1, T.magSlots do
        local e = type(s.slots) == 'table' and s.slots[g] or false
        if e then
            rows[#rows + 1] = {
                id = 'slot' .. g,
                label = ('Slot %d · %s · %d/%d full'):format(g, e.label or '?', e.full or 0, e.n or 0),
                options = {
                    { id = 'take', label = ('Remove magazines · %d'):format(e.n or 0),
                      onSelect = function() TriggerServerEvent('norte_bancada:take', m.id, 'mags', g) end },
                },
            }
        else
            rows[#rows + 1] = {
                id = 'slot' .. g,
                label = ('Slot %d · empty'):format(g),
                options = function() return pocketOptions(m.id, 'mags', g) end,
            }
        end
    end
    return rows
end

local function isPoint(p) return p and p.x and p.y and p.z end

local function at(m, p)
    return worldPoint(m, vector3(p.x, p.y, p.z)), ((m.h or 0.0) + (p.w or 0.0)) % 360.0
end

--- Tira todos os prompts de uma máquina: o único e os três separados.
local function removeActions(id)
    Whip.core:RemoveAction('maquina_' .. id)
    for _, part in ipairs(PARTS) do Whip.core:RemoveAction(('maquina_%s_%s'):format(id, part)) end
end

--- Os prompts da máquina. Com promptPlaced e promptPoints no tipo, há três, cada um no seu ponto (tirado com /int).
--- Com promptPlaced só, um no promptPoint. Sem ele, um que espera pelas medidas do modelo e fica no lado de
--- Config.PromptSide.
local function addAction(m)
    local T = Config.TypeOf(m.kind)
    if T.promptPlaced and type(T.promptPoints) == 'table' then
        for _, part in ipairs(PARTS) do
            local p = T.promptPoints[part]
            if isPoint(p) then
                local coords, heading = at(m, p)
                addActionAt(m, coords, heading, part)
            end
        end
        return
    end
    local p = T.promptPlaced and T.promptPoint
    if isPoint(p) then
        addActionAt(m, at(m, p))
        return
    end
    CreateThread(function()
        local hash = loadModel(T.model)
        if Machines[m.id] ~= m then return end   -- tirada entretanto
        local coords, heading
        if hash then
            coords, heading = sidePrompt(m, hash)
            SetModelAsNoLongerNeeded(hash)
        else
            coords = worldPoint(m, Config.Point)
        end
        addActionAt(m, coords, heading)
    end)
end

--- part: nil para o prompt único com tudo, ou 'ammo', 'mags' ou 'machine' para um dos três separados.
function addActionAt(m, coords, heading, part)
    local id = m.id
    local function st() return m.state or {} end
    local function slotted() return Config.TypeOf(m.kind).magSlots ~= nil end

    local options = {
            { id = 'mag_add', label = 'Add magazines',
              canInteract = function() local s = st() return not slotted() and not s.working and not s.magItem end,
              options = function() return pocketOptions(id, 'mags') end },
            { id = 'mag_take',
              label = function() local s = st() return ('Remove magazines · %d/%d full'):format(s.full or 0, s.mags or 0) end,
              canInteract = function() local s = st() return not slotted() and not s.working and s.magItem ~= nil end,
              onSelect = function() TriggerServerEvent('norte_bancada:take', id, 'mags', 0) end },
            { id = 'slots',
              label = function() local s = st() return ('Magazine slots · %d/%d'):format(s.mags or 0, Config.TypeOf(m.kind).maxMags) end,
              canInteract = function() return slotted() and not st().working end,
              options = function() return slotRows(m) end },
            { id = 'ammo_add', label = 'Add rounds',
              canInteract = function() local s = st() return not s.working and not s.ammoItem end,
              options = function() return pocketOptions(id, 'ammo') end },
            { id = 'ammo_take',
              label = function() local s = st() return ('Remove rounds · %d'):format(s.rounds or 0) end,
              canInteract = function() local s = st() return not s.working and s.ammoItem ~= nil end,
              onSelect = function() TriggerServerEvent('norte_bancada:take', id, 'ammo', 0) end },
            { id = 'start', label = 'Start',
              canInteract = function() local s = st() return not s.working and s.ammoItem ~= nil and s.magItem ~= nil end,
              onSelect = function() TriggerServerEvent('norte_bancada:start', id) end },
            { id = 'stop', label = 'Stop',
              canInteract = function() return st().working == true end,
              onSelect = function() TriggerServerEvent('norte_bancada:stop', id) end },
            { id = 'store', label = 'Pack up machine', require = { charId = m.owner }, holdMs = 1000,
              onSelect = function() TriggerServerEvent('norte_bancada:pickup', id) end },
    }
    if part then
        local keep = {}
        for _, o in ipairs(options) do
            if PART_OPTIONS[part][o.id] then keep[#keep + 1] = o end
        end
        options = keep
    end

    Whip.core:AddAction({
        id = part and ('maquina_%s_%s'):format(id, part) or ('maquina_' .. id), group = 'maquinas',
        at = { coords = coords, heading = heading },
        scale = Config.PromptScale,
        label = function()
            local s = st()
            if part == 'ammo' then return 'Rounds' end
            if part == 'mags' then return 'Magazines' end
            if s.working then
                return ('Loading · %d/%d'):format(s.loaded or 0, s.total or 0)
            end
            return Config.TypeOf(m.kind).label
        end,
        reach = Config.Reach,
        options = options,
    })
end

-- ===================================================================================================
-- Lista de máquinas, vinda do servidor
-- ===================================================================================================

local function dropMachine(id)
    local m = Machines[id]
    if not m then return end
    Machines[id] = nil
    despawn(m)
    removeActions(id)
end

local function setMachine(data)
    if type(data) ~= 'table' or not data.id or not data.coords then return end
    dropMachine(data.id)
    local m = { id = data.id, kind = data.kind, owner = data.owner, coords = data.coords, h = data.h or 0.0, state = data.state or false }
    Machines[m.id] = m
    addAction(m)
end

local function setAll(list)
    for id in pairs(Machines) do dropMachine(id) end
    for _, data in ipairs(type(list) == 'table' and list or {}) do setMachine(data) end
end

RegisterNetEvent('norte_bancada:client:all', setAll)

-- Um admin mudou o prompt em /whip → Settings: todos os prompts voltam a ser postos, já com os valores novos.
for _, key in ipairs({ 'PromptSide', 'PromptHeight', 'PromptGap', 'PromptScale',
                       'Types.norte_bancada.promptPlaced', 'Types.norte_bancada.promptPoint',
                       'Types.norte_bancada.promptPoints.ammo', 'Types.norte_bancada.promptPoints.mags',
                       'Types.norte_bancada.promptPoints.machine',
                       'Types.norte_bancada_mk2.promptPlaced', 'Types.norte_bancada_mk2.promptPoint' }) do
    Whip.onConfigChanged(key, function()
        for id, m in pairs(Machines) do
            removeActions(id)
            addAction(m)
        end
    end)
end
RegisterNetEvent('norte_bancada:client:add', setMachine)
RegisterNetEvent('norte_bancada:client:remove', dropMachine)

RegisterNetEvent('norte_bancada:client:state', function(id, state)
    local m = Machines[id]
    if not m then return end
    m.state = state or false
    if m.obj then CreateThread(function() syncParts(m) end) end
end)

-- ===================================================================================================
-- Colocar: um fantasma da máquina segue o olhar, e só se coloca onde ela cabe
-- ===================================================================================================
--
-- O PlaceObject do WHIP não testa colisões (só lê label, reach e vehicles), por isso a máquina entrava pelos muros.
-- Este colocador testa a caixa do modelo (GetModelDimensions) contra o mundo, carros e objetos a cada frame, e só
-- deixa colocar numa superfície plana. Scroll roda, E coloca, C ou Backspace cancela.

local CTRL_PLACE, CTRL_CANCEL, CTRL_BACK = 38, 26, 177
local CTRL_WHEEL_UP, CTRL_WHEEL_DOWN = 241, 242
local DISABLED = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 241, 242, 26, 177 }

local function camDirection()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    return vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
end

--- O ponto que a câmara vê, até Config.PlaceReach metros: coords e normal, ou nil.
local function aimPoint(ped)
    local from = GetGameplayCamCoord()
    local to = from + camDirection() * (Config.PlaceReach + #(from - GetEntityCoords(ped)))
    local probe = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 | 16, ped, 7)
    local _, hit, coords, normal = GetShapeTestResult(probe)
    if hit ~= 1 then return nil end
    return coords, normal
end

--- Rodar um ponto do referencial do prop pelo heading.
local function rotated(v, h)
    local r = math.rad(h)
    local c, s = math.cos(r), math.sin(r)
    return vector3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
end

--- Começa o teste da caixa da máquina naquele sítio (assíncrono: a resposta chega num frame seguinte).
local function startRoomTest(pos, h, dmin, dmax, ignore)
    local size = (dmax - dmin) * Config.PlaceShrink
    local centre = (dmin + dmax) * 0.5
    local c = pos + rotated(vector3(centre.x, centre.y, centre.z + Config.PlaceLift * 0.5), h)
    return StartShapeTestBox(c.x, c.y, c.z, size.x, size.y, size.z - Config.PlaceLift, 0.0, 0.0, h, 2, 1 | 2 | 16, ignore, 4)
end

local function placeMode(kind)
    local ped = PlayerPedId()
    local hash = loadModel(Config.TypeOf(kind).model)
    if not hash then return nil end
    local dmin, dmax = GetModelDimensions(hash)

    local ghost = CreateObjectNoOffset(hash, 0.0, 0.0, -100.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityAlpha(ghost, 170, false)

    local heading = GetEntityHeading(ped)
    local test, blocked = nil, true
    local spot, ok, lastHint
    local function hint(text, warn)
        if text == lastHint then return end
        lastHint = text
        Whip.core:ShowText(text, { position = 'bottom', icon = 'place', tone = warn and 'warn' or nil })
    end

    while true do
        for i = 1, #DISABLED do DisableControlAction(0, DISABLED[i], true) end

        if IsDisabledControlJustPressed(0, CTRL_WHEEL_UP) then heading = heading + Config.PlaceRotateStep end
        if IsDisabledControlJustPressed(0, CTRL_WHEEL_DOWN) then heading = heading - Config.PlaceRotateStep end
        heading = heading % 360.0

        local coords, normal = aimPoint(ped)
        local why
        if not coords then
            why = 'Look at the ground'
        elseif normal.z < Config.PlaceFlat then
            why = 'Needs a flat surface'
        elseif #(coords - GetEntityCoords(ped)) > Config.PlaceRange - 0.5 then
            why = 'Too far away'
        end

        if coords then
            SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z, false, false, false)
            SetEntityRotation(ghost, 0.0, 0.0, heading, 2, false)
            -- O teste da caixa: lê o anterior quando estiver pronto, e lança o seguinte.
            if test then
                local state, hit = GetShapeTestResult(test)
                if state ~= 1 then
                    blocked = hit == 1
                    test = nil
                end
            end
            if not test then test = startRoomTest(coords, heading, dmin, dmax, ghost) end
            if not why and blocked then why = 'Not enough room here' end
        else
            SetEntityCoordsNoOffset(ghost, 0.0, 0.0, -100.0, false, false, false)
        end

        ok = why == nil
        SetEntityAlpha(ghost, ok and 200 or 90, false)
        if ok then
            spot = { coords = coords, heading = heading }
            hint('[E] Place  |  [Scroll] Rotate  |  [C] Cancel')
        else
            spot = nil
            hint(why .. '  |  [C] Cancel', true)
        end

        if IsDisabledControlJustPressed(0, CTRL_CANCEL) or IsDisabledControlJustPressed(0, CTRL_BACK)
            or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
            spot = nil
            break
        end
        if ok and IsDisabledControlJustPressed(0, CTRL_PLACE) then break end
        Wait(0)
    end

    deleteObj(ghost)
    Whip.core:HideText()
    return spot
end

-- O servidor manda colocar quando o jogador usa o item.
RegisterNetEvent('norte_bancada:client:place', function(kind)
    if placing then return end
    placing = true
    CreateThread(function()
        local ok, spot = pcall(placeMode, kind)
        placing = false
        if not ok or not spot then return end
        TriggerServerEvent('norte_bancada:place', kind, spot.coords.x, spot.coords.y, spot.coords.z, spot.heading)
    end)
end)

-- ===================================================================================================
-- Ciclos: criar os objetos por perto, e o som
-- ===================================================================================================

-- De segundo a segundo: a máquina aparece a menos de Config.DrawRange e desaparece para lá disso.
CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, m in pairs(Machines) do
            local near = #(pos - m.coords) < Config.DrawRange
            if near and not m.obj then spawn(m)
            elseif not near and m.obj then despawn(m) end
        end
        Wait(1000)
    end
end)

-- O som da máquina a trabalhar (html/sounds), em loop, mais baixo com a distância. De 250 em 250 ms: a máquina a
-- trabalhar mais perto, até Config.SoundRange, dá o volume; nenhuma, silêncio.
CreateThread(function()
    local lastVolume = 0.0
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local bestDist
        for _, m in pairs(Machines) do
            if m.state and m.state.working then
                local d = #(pos - m.coords)
                if d < Config.SoundRange and (not bestDist or d < bestDist) then bestDist = d end
            end
        end
        local volume = 0.0
        if bestDist then
            local near = 1.0 - bestDist / Config.SoundRange
            volume = Config.SoundVolume * near * near
        end
        if math.abs(volume - lastVolume) > 0.01 or (volume == 0.0 and lastVolume ~= 0.0) then
            lastVolume = volume
            SendNUIMessage({ action = 'sound', volume = volume, fadeIn = Config.SoundFadeIn, fadeOut = Config.SoundFadeOut })
        end
        Wait(250)
    end
end)

-- ===================================================================================================
-- O ecrã da MK2: a textura do modelo passa a ser uma página DUI (html/screen.html)
-- ===================================================================================================
--
-- AddReplaceTexture troca a textura do modelo, não a de um objeto: todas as MK2 deste jogo mostram o mesmo ecrã.
-- Mostra a MK2 criada mais perto. A DUI só existe enquanto há uma MK2 criada (a menos de Config.DrawRange).

local SCREEN_TXD = 'norte_bancada_screen'
local screen = nil   -- { dui, kind, def } enquanto a textura do modelo está trocada
local duis = {}      -- [tipo] = a DUI desse tipo; feita uma vez, a textura de runtime não se pode refazer com o mesmo nome
local screenTxd = nil

local function openScreen(kind, def)
    local dui = duis[kind]
    if not dui then
        dui = CreateDui(('nui://%s/html/screen.html'):format(GetCurrentResourceName()), def.width, def.height)
        if not dui then return end
        screenTxd = screenTxd or CreateRuntimeTxd(SCREEN_TXD)
        CreateRuntimeTextureFromDuiHandle(screenTxd, kind, GetDuiHandle(dui))
        duis[kind] = dui
    end
    AddReplaceTexture(def.txd, def.texture, SCREEN_TXD, kind)
    screen = { dui = dui, kind = kind, def = def }
end

--- Devolve a textura original ao modelo. A DUI fica (parada) para a próxima vez; destroy = true apaga-as todas.
local function closeScreen(destroy)
    if screen then
        RemoveReplaceTexture(screen.def.txd, screen.def.texture)
        screen = nil
    end
    if destroy then
        for kind, dui in pairs(duis) do
            DestroyDui(dui)
            duis[kind] = nil
        end
    end
end

--- O que o ecrã mostra: a carregar (loaded/total do trabalho) ou parado (cheios/carregadores).
local function screenPayload(m)
    local s = m.state or {}
    return json.encode({
        action = 'state', title = Config.TypeOf(m.kind).screen.title,
        working = s.working == true,
        done = not s.working and (s.mags or 0) > 0 and (s.full or 0) >= (s.mags or 0),
        loaded = s.loaded or 0, total = s.total or 0,
        mags = s.mags or 0, full = s.full or 0, magLabel = s.magLabel, rounds = s.rounds or 0,
    })
end

-- De 500 em 500 ms: abre ou fecha a DUI e manda-lhe o estado quando muda (e de 2 em 2 s, para uma página que
-- ainda estava a carregar).
CreateThread(function()
    local last, lastAt = nil, 0
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local best, bestDist
        for _, m in pairs(Machines) do
            local T = Config.TypeOf(m.kind)
            if T.screen and m.obj then
                local d = #(pos - m.coords)
                if not bestDist or d < bestDist then best, bestDist = m, d end
            end
        end

        if best then
            local T = Config.TypeOf(best.kind)
            if screen and screen.kind ~= best.kind then closeScreen() end
            if not screen then
                openScreen(best.kind, T.screen)
                last = nil
            end
            if screen then
                local payload = screenPayload(best)
                if payload ~= last or GetGameTimer() - lastAt > 2000 then
                    last, lastAt = payload, GetGameTimer()
                    SendDuiMessage(screen.dui, payload)
                end
            end
        elseif screen then
            closeScreen()
        end
        Wait(500)
    end
end)

Whip.register(function()
    CreateThread(function()
        local list = Whip.core:Callback('norte_bancada:list')
        if type(list) == 'table' then setAll(list) end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, m in pairs(Machines) do despawn(m) end
    closeScreen(true)
    SendNUIMessage({ action = 'sound', volume = 0 })
end)
