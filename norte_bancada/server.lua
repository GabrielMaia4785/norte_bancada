-- norte_bancada — servidor
--
-- Cada máquina colocada é um contentor do WHIP (CreateContainer, trancado e sem prop): o WHIP guarda o que está lá
-- dentro na base de dados, e trancado não mostra o prompt "abrir". Só este recurso lhe mexe. A lista de máquinas
-- (id do contentor, dono, posição) fica no KVP do recurso. O prop, a caixa e o carregador são do cliente.
--
-- A máquina leva um tipo de balas e um tipo de carregador de cada vez. "Iniciar" carrega até os carregadores
-- encherem ou as balas acabarem, Config.TickMs de cada vez, e só aí se pode mexer de novo nela.

local KVP = 'norte_bancada:maquinas'

local Machines = {}   -- [containerId] = { id, kind = tipo (Config.Types), owner = charId, coords = vector3, h }
local Mags = {}       -- [item do carregador] = definição do whip_gunny (caliber, capacity, prop)
local Calibers = {}   -- [calibre] = definição do whip_gunny (ammoItem, label, prop)
local AmmoItems = {}  -- [item de munição] = calibre
local Allowed = {}    -- os itens que entram na máquina
local jobs = {}       -- [id] = { loaded, total, by = source, session } enquanto a máquina carrega
local sent = {}       -- [id] = o último estado enviado aos clientes
local busy = {}       -- [source] = true durante um pedido

local function warn(fmt, ...)
    print(('^3[norte_bancada] ' .. fmt .. '^0'):format(...))
end

-- ===================================================================================================
-- Dados do whip_gunny
-- ===================================================================================================

--- Lê items/calibers.lua e items/magazines.lua do whip_gunny num ambiente à parte. O gunny não exporta estas
--- tabelas. Carregadores de packs de outros recursos (RegisterMagazine) não entram.
local function loadGunny()
    local env = setmetatable({ Config = {} }, { __index = _G })
    for _, path in ipairs({ 'items/calibers.lua', 'items/magazines.lua' }) do
        local code = LoadResourceFile('whip_gunny', path)
        if not code then
            warn('o whip_gunny não tem %s', path)
            return false
        end
        local fn, err = load(code, '@whip_gunny/' .. path, 't', env)
        if not fn then
            warn('não consegui ler %s: %s', path, tostring(err))
            return false
        end
        local ok, runErr = pcall(fn)
        if not ok then
            warn('erro ao ler %s: %s', path, tostring(runErr))
            return false
        end
    end

    Calibers = env.Config.Calibers or {}
    Mags = env.Config.Magazines or {}
    AmmoItems, Allowed = {}, {}
    for name, caliber in pairs(Calibers) do
        if caliber.ammoItem then
            AmmoItems[caliber.ammoItem] = name
            Allowed[#Allowed + 1] = caliber.ammoItem
        end
    end
    for item in pairs(Mags) do Allowed[#Allowed + 1] = item end
    return true
end

--- A capacidade em vigor: a do /whip → Items, se um admin a mudou, senão a do gunny.
local function capacityOf(item)
    local mag = Mags[item]
    if not mag then return nil end
    return tonumber(exports.whip_core:GetItemSetting(item, 'capacity')) or tonumber(mag.capacity)
end

local function ammoItemOf(magItem)
    local mag = Mags[magItem]
    local caliber = mag and Calibers[mag.caliber]
    return caliber and caliber.ammoItem
end

local function labelOf(item)
    local def = exports.whip_core:GetItemDef(item)
    return def and def.name or item
end

-- ===================================================================================================
-- Máquinas: guardar, ler, avisar os clientes
-- ===================================================================================================

local function storeOf(id) return { kind = 'container', id = id } end

local function save()
    local list = {}
    for id, m in pairs(Machines) do
        list[#list + 1] = { id = id, kind = m.kind, owner = m.owner, x = m.coords.x, y = m.coords.y, z = m.coords.z, h = m.h }
    end
    SetResourceKvp(KVP, json.encode(list))
end

local function loadSaved()
    local raw = GetResourceKvpString(KVP)
    if not raw or raw == '' then return {} end
    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' then
        warn('a lista de máquinas guardada está estragada; começo vazia')
        return {}
    end
    return list
end

-- Máquinas com slots (magSlots no tipo, a MK2): o slot g do prompt são os lugares (g-1)*perSlot+1 a g*perSlot do
-- contentor, e as balas vão para os lugares a seguir a todos esses.
local function slotRange(T, g)
    local first = (g - 1) * T.perSlot + 1
    return first, first + T.perSlot - 1
end

local function firstAmmoSlot(T)
    return T.magSlots and (T.magSlots * T.perSlot + 1) or nil
end

--- O que está dentro da máquina: o tipo de balas e quantas, o tipo de carregador e cada carregador.
local function readMachine(id)
    local contents = Whip.core:StoreRead(storeOf(id))
    if not contents then return nil end
    local s = { rounds = 0, ammo = {}, mags = {}, full = 0, space = 0, items = contents.items or {} }
    for slot, it in pairs(contents.items or {}) do
        if it and AmmoItems[it.item] then
            local n = tonumber(it.amount) or 0
            s.ammo[it.item] = (s.ammo[it.item] or 0) + n
            s.rounds = s.rounds + n
            s.ammoItem = s.ammoItem or it.item
        elseif it and Mags[it.item] then
            local cap = capacityOf(it.item) or 0
            local have = tonumber(it.metadata and it.metadata.ammo) or 0
            if have >= cap then s.full = s.full + 1 end
            s.space = s.space + math.max(0, cap - have)
            s.mags[#s.mags + 1] = { slot = slot, item = it.item, ammo = have, cap = cap, meta = it.metadata or {} }
            s.magItem = s.magItem or it.item
        end
    end
    table.sort(s.mags, function(a, b) return a.slot < b.slot end)
    return s
end

--- O estado que os clientes recebem: o que mostrar no prompt, que modelos encaixar e o progresso.
local function stateOf(id, s)
    if not s then return false end
    local job = jobs[id]
    local caliber = s.ammoItem and Calibers[AmmoItems[s.ammoItem]]
    local mag = s.magItem and Mags[s.magItem]
    local state = {
        ammoItem = s.ammoItem, ammoLabel = s.ammoItem and labelOf(s.ammoItem), rounds = s.rounds,
        magItem = s.magItem, magLabel = s.magItem and labelOf(s.magItem), mags = #s.mags, full = s.full,
        boxProp = caliber and caliber.prop or nil, magProp = mag and mag.prop or nil,
        working = job ~= nil, loaded = job and job.loaded or 0, total = job and job.total or 0,
    }

    -- Com slots: o que tem cada slot (para o prompt) e o modelo em cada lugar do contentor (para desenhar).
    local T = Config.TypeOf(Machines[id] and Machines[id].kind)
    if T.magSlots then
        local places = T.magSlots * T.perSlot
        state.slots, state.magPos = {}, {}
        for p = 1, places do state.magPos[p] = false end
        for g = 1, T.magSlots do state.slots[g] = false end
        for _, m in ipairs(s.mags) do
            if m.slot <= places then
                local g = math.ceil(m.slot / T.perSlot)
                local def = Mags[m.item]
                state.magPos[m.slot] = def and def.prop or false
                local e = state.slots[g] or { label = labelOf(m.item), n = 0, full = 0 }
                e.n = e.n + 1
                if m.ammo >= m.cap then e.full = e.full + 1 end
                state.slots[g] = e
            end
        end
    end
    return state
end

local function sameValue(a, b)
    if type(a) == 'table' and type(b) == 'table' then return json.encode(a) == json.encode(b) end
    return a == b
end

local function sameState(a, b)
    if not a or not b then return a == b end
    for k, v in pairs(a) do if not sameValue(b[k], v) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function refresh(id)
    if not Machines[id] then return end
    local state = stateOf(id, readMachine(id))
    if sameState(sent[id], state) then return end
    sent[id] = state or nil
    TriggerClientEvent('norte_bancada:client:state', -1, id, state)
end

local function packMachine(id)
    local m = Machines[id]
    return m and { id = id, kind = m.kind, owner = m.owner, coords = m.coords, h = m.h, state = sent[id] or false }
end

-- ===================================================================================================
-- O carregamento
-- ===================================================================================================

--- Um passo: até `budget` balas, carregador a carregador. Devolve quantas meteu.
local function tick(id, budget)
    local s = readMachine(id)
    if not s then return 0 end

    budget = math.max(1, budget)
    local loaded = 0

    for _, mag in ipairs(s.mags) do
        if budget <= 0 then break end
        local ammoItem = ammoItemOf(mag.item)
        local have = ammoItem and s.ammo[ammoItem] or 0
        local space = mag.cap - mag.ammo
        if space > 0 and have > 0 then
            local n = math.min(space, have, budget)
            local slotAddr = { kind = 'container', id = id, slot = mag.slot }

            -- Tirar antes de dar: as balas saem do contentor, depois entram no carregador.
            local taken = Whip.core:StoreTake(storeOf(id), n, { item = ammoItem, reason = 'norte_bancada: carregador' })
            if taken then
                local now = Whip.core:GetItemAt(slotAddr)
                local nowMeta = now and now.metadata or {}
                local same = now and now.item == mag.item
                    and (tonumber(nowMeta.ammo) or 0) == mag.ammo
                    and nowMeta.serial == mag.meta.serial
                if same and Whip.core:SetItemMetadata(slotAddr, { ammo = mag.ammo + n }) then
                    loaded = loaded + n
                    budget = budget - n
                    s.ammo[ammoItem] = have - n
                elseif not Whip.core:StoreGive(storeOf(id), ammoItem, n, nil, 'norte_bancada: devolvidas') then
                    warn('máquina %d: %d balas de %s PERDIDAS (o carregador mudou e não couberam de volta)', id, n, ammoItem)
                end
            end
        end
    end

    return loaded
end

--- Corre o trabalho da máquina até não haver mais nada para carregar, ou até alguém a parar (jobs[id] muda).
local function run(id, job)
    CreateThread(function()
        while Machines[id] and jobs[id] == job do
            -- Lido a cada passo: o /whip → Settings muda a velocidade a meio. Um passo dura pelo menos uma bala.
            local stepMs = math.max(Config.TickMs, Config.MsPerRound)
            Wait(stepMs)
            if jobs[id] ~= job or not Machines[id] then return end   -- parada: o stop já avisou
            local n = tick(id, math.floor(stepMs / Config.MsPerRound))
            job.loaded = math.min(job.total, job.loaded + n)
            if n < 1 or job.loaded >= job.total then break end
            refresh(id)
        end
        if jobs[id] ~= job then return end
        jobs[id] = nil
        refresh(id)
        if job and job.by and exports.whip_core:IsSessionCurrent(job.by, job.session) then
            exports.whip_core:NotifyPlayer(job.by, ('Machine finished: %d rounds loaded'):format(job.loaded), 'success')
        end
    end)
end

-- ===================================================================================================
-- Pedidos dos jogadores
-- ===================================================================================================

local function nearMachine(source, id)
    local m = Machines[id]
    if not m then return nil, 'That machine is gone' end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil, 'Move closer to the machine' end
    if #(GetEntityCoords(ped) - m.coords) > Config.UseRange then return nil, 'Move closer to the machine' end
    return m
end

--- Corre `fn` com um pedido de cada vez por jogador, sem deixar o flag preso se der erro.
local function guarded(source, fn, ...)
    if busy[source] then return false, 'Wait a moment' end
    busy[source] = true
    local ran, ok, why = pcall(fn, ...)
    busy[source] = nil
    if not ran then
        warn('erro: %s', tostring(ok))
        return false, 'Could not do that'
    end
    return ok, why
end

--- Os carregadores de um tipo que o jogador tem por encher, do mais vazio para o mais cheio.
local function unfilledMags(source, item)
    local cap = capacityOf(item) or 0
    local list = {}
    for _, found in ipairs(exports.whip_core:FindAllItems(source, item) or {}) do
        local have = tonumber(found.metadata and found.metadata.ammo) or 0
        if have < cap then list[#list + 1] = { addr = found.addr, ammo = have } end
    end
    table.sort(list, function(a, b) return a.ammo < b.ammo end)
    return list
end

--- O que o jogador pode pôr num lado da máquina: { item, label, count }. count são balas, ou carregadores por encher.
local function pocketList(source, side)
    local out = {}
    if side == 'ammo' then
        for item in pairs(AmmoItems) do
            local count = exports.whip_core:GetItemCount(source, item) or 0
            if count > 0 then out[#out + 1] = { item = item, label = labelOf(item), count = count } end
        end
    else
        -- Todos os tipos que o jogador tem: count os por encher, total todos (os cheios aparecem, mas não entram).
        for item in pairs(Mags) do
            local total = #(exports.whip_core:FindAllItems(source, item) or {})
            if total > 0 then
                out[#out + 1] = { item = item, label = labelOf(item), count = #unfilledMags(source, item), total = total }
            end
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

--- Os lugares vazios de um slot (máquina com slots), do primeiro ao último.
local function freePlaces(T, s, g)
    local list = {}
    local first, last = slotRange(T, g)
    for p = first, last do
        if not s.items[p] then list[#list + 1] = p end
    end
    return list
end

--- Um lugar vazio para balas, a seguir aos dos carregadores (máquina com slots). `used`: os já escolhidos agora.
local function freeAmmoPlace(T, s, used)
    for p = firstAmmoSlot(T), T.slots do
        if not s.items[p] and not used[p] then return p end
    end
end

--- Já há carregadores neste slot?
local function slotTaken(T, s, g)
    local first, last = slotRange(T, g)
    for _, m in ipairs(s.mags) do
        if m.slot >= first and m.slot <= last then return true end
    end
    return false
end

--- Põe balas ou carregadores na máquina: confirma, faz a animação (barra do servidor), confirma de novo e move.
--- slot: numa máquina com slots, o slot (1 a magSlots) onde vão os carregadores; 0 nas outras.
local function put(source, player, id, side, item, amount, slot)
    local isAmmo = side == 'ammo'
    if isAmmo and not AmmoItems[item] then return false, 'That is not ammunition' end
    if not isAmmo and not Mags[item] then return false, 'That is not a magazine' end
    if jobs[id] then return false, 'The machine is running' end

    local T = Config.TypeOf(Machines[id].kind)
    local s = readMachine(id)
    if not s then return false, 'Could not open the machine' end
    if isAmmo and s.ammoItem then return false, 'The machine already has rounds' end
    if not isAmmo and T.magSlots then
        if slot < 1 or slot > T.magSlots then return false, 'Choose a slot' end
        if slotTaken(T, s, slot) then return false, 'That slot already has magazines' end
        if #freePlaces(T, s, slot) < 1 then return false, 'That slot is blocked: take the rounds out first' end
    elseif not isAmmo and s.magItem then
        return false, 'The machine already has magazines'
    end
    if isAmmo and (exports.whip_core:GetItemCount(source, item) or 0) < 1 then return false, 'You have none of those rounds' end
    if not isAmmo and #unfilledMags(source, item) < 1 then return false, 'You have no empty magazines of that type' end

    local m = Machines[id]
    local caliber = isAmmo and Calibers[AmmoItems[item]]
    local inHand = isAmmo and (caliber and caliber.prop) or (Mags[item] and Mags[item].prop)
    local done = Whip.core:Progress(source, {
        label     = isAmmo and 'Loading rounds into the machine' or 'Loading magazines into the machine',
        duration  = Config.PutMs,
        canCancel = true,
        item      = item,
        anim      = Config.PutAnim,
        prop      = inHand and { model = inHand, bone = 57005, offset = { 0.12, 0.02, -0.02 }, rot = { -90.0, 0.0, 0.0 } } or nil,
        near      = { coords = m.coords, range = Config.UseRange + 0.5 },
        notWhile  = { 'swimming', 'falling' },
    })
    if not done then return false end

    -- A barra demorou: tudo de novo.
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not Machines[id] then return false, 'That machine is gone' end
    if jobs[id] then return false, 'The machine is running' end
    s = readMachine(id)
    local changed = not s or (isAmmo and s.ammoItem)
    if not changed and not isAmmo then
        if T.magSlots then changed = slotTaken(T, s, slot) else changed = s.magItem ~= nil end
    end
    if changed then return false, 'Someone changed the machine' end

    local moved, why = 0, nil
    if isAmmo then
        local left, used = amount, {}
        for _, stack in ipairs(exports.whip_core:FindAllItems(source, item) or {}) do
            if left <= 0 then break end
            local n = math.min(left, tonumber(stack.amount) or 0)
            if n > 0 then
                -- Com slots, cada monte de balas vai para um lugar a seguir aos dos carregadores.
                local to = storeOf(id)
                if T.magSlots then
                    local p = freeAmmoPlace(T, s, used)
                    if not p then why = 'The machine is full' break end
                    used[p], to.slot = true, p
                end
                local ok, err = exports.whip_core:StoreMove(stack.addr, to, { amount = n, reason = 'norte_bancada: balas na máquina' })
                if not ok then why = err break end
                left = left - n
            end
        end
        moved = amount - left
    elseif T.magSlots then
        -- Os carregadores vão para os lugares vazios do slot escolhido, até perSlot.
        local places = freePlaces(T, s, slot)
        for _, mag in ipairs(unfilledMags(source, item)) do
            if moved >= math.min(amount, #places) then break end
            local to = { kind = 'container', id = id, slot = places[moved + 1] }
            local ok, err = exports.whip_core:StoreMove(mag.addr, to, { reason = 'norte_bancada: carregador na máquina' })
            if not ok then why = err break end
            moved = moved + 1
        end
    else
        -- No máximo o maxMags do tipo da máquina: o cliente só oferece até lá, mas quem decide é o servidor.
        amount = math.min(amount, Config.TypeOf(m.kind).maxMags - #s.mags)
        for _, mag in ipairs(unfilledMags(source, item)) do
            if moved >= amount then break end
            local ok, err = exports.whip_core:StoreMove(mag.addr, storeOf(id), { reason = 'norte_bancada: carregador na máquina' })
            if not ok then why = err break end
            moved = moved + 1
        end
    end

    if moved < 1 then return false, why or 'Could not do that' end
    exports.whip_core:NotifyPlayer(source, isAmmo and ('Added %d rounds'):format(moved)
        or ('Added %d magazine(s)'):format(moved), 'success')
    if why then exports.whip_core:NotifyPlayer(source, why, 'error') end
    return true
end

--- Tira um lado da máquina para os bolsos. Devolve o que tirou e, se algo ficou, porquê.
--- group: numa máquina com slots, só os carregadores desse slot (0 ou nil: todos).
local function takeSide(source, id, side, group)
    local contents = exports.whip_core:StoreRead(storeOf(id))
    if not contents then return 0, 'Could not open the machine' end
    local pockets = { kind = 'player', id = source, sub = 'player' }
    local T = Config.TypeOf(Machines[id] and Machines[id].kind)
    local first, last = 1, math.huge
    if group and group > 0 and T.magSlots then first, last = slotRange(T, group) end
    local moved = 0
    for slot, it in pairs(contents.items or {}) do
        local match = it and ((side == 'ammo' and AmmoItems[it.item]) or (side == 'mags' and Mags[it.item]))
            and slot >= first and slot <= last
        if match then
            local ok, err = exports.whip_core:StoreMove({ kind = 'container', id = id, slot = slot }, pockets,
                { reason = 'norte_bancada: retirado da máquina' })
            if not ok then return moved, err or 'No room in your pockets' end
            moved = moved + (side == 'ammo' and (tonumber(it.amount) or 0) or 1)
        end
    end
    return moved
end

local function take(source, id, side, group)
    if jobs[id] then return false, 'The machine is running' end
    local moved, why = takeSide(source, id, side, group)
    if moved < 1 then
        return false, why or (side == 'ammo' and 'The machine has no rounds'
            or (group and group > 0) and 'That slot has no magazines' or 'The machine has no magazines')
    end
    exports.whip_core:NotifyPlayer(source,
        side == 'ammo' and ('Took out %d rounds'):format(moved) or ('Took out %d magazine(s)'):format(moved), 'success')
    if why then exports.whip_core:NotifyPlayer(source, why, 'error') end
    return true
end

local function start(source, player, id)
    if jobs[id] then return false, 'The machine is already running' end
    local s = readMachine(id)
    if not s or not s.ammoItem or not s.magItem then return false, 'Add rounds and magazines first' end
    -- Só contam os carregadores destas balas (na MK2 cada slot pode ter um tipo diferente).
    local space, fits = 0, false
    for _, m in ipairs(s.mags) do
        if ammoItemOf(m.item) == s.ammoItem then
            fits = true
            space = space + math.max(0, m.cap - m.ammo)
        end
    end
    if not fits then return false, 'These rounds do not fit these magazines' end
    local total = math.min(space, s.ammo[s.ammoItem] or 0)
    if total < 1 then return false, 'The magazines are already full' end
    local job = { loaded = 0, total = total, by = source, session = player.session }
    jobs[id] = job
    refresh(id)
    run(id, job)
    return true
end

--- Pára a máquina a meio: o que já entrou nos carregadores fica, as balas que sobram ficam na máquina.
local function stop(source, id)
    local job = jobs[id]
    if not job then return false, 'The machine is not running' end
    jobs[id] = nil
    refresh(id)
    exports.whip_core:NotifyPlayer(source, ('Machine stopped: %d rounds loaded'):format(job.loaded), 'success')
    return true
end

local function place(source, player, kind, x, y, z, h)
    local T = Config.Types[kind]
    if not T then return false, 'Unknown machine' end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false, 'Could not do that' end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false, 'Get out of the vehicle first' end
    local coords = vector3(x, y, z)
    if #(GetEntityCoords(ped) - coords) > Config.PlaceRange then return false, 'That spot is too far away' end
    for _, m in pairs(Machines) do
        if #(m.coords - coords) < Config.MinSpacing then return false, 'Another machine is there' end
    end

    local found = exports.whip_core:FindItem(source, kind)
    if not found then return false, 'You no longer have the machine' end
    local taken, err = exports.whip_core:StoreTake(found.addr, 1, 'norte_bancada: colocada')
    if not taken then return false, err end

    -- Trancado: o WHIP não lhe dá o prompt "abrir", e só este recurso move o que está lá dentro.
    local created, why = exports.whip_core:CreateContainer({
        name = T.label, type = 'norte_bancada',
        x = x, y = y, z = z, heading = h,
        prop = false, placed = true, rx = 0.0, ry = 0.0, locked = true,
        slots = T.slots, maxWeight = T.maxWeight,
        allowedItems = Allowed,
    })
    if not created then
        exports.whip_core:AddItem(source, kind, 1, nil, 'norte_bancada: colocação falhou')
        return false, why or 'Could not place the machine'
    end

    local id = created.containerId
    Machines[id] = { id = id, kind = kind, owner = player.charId, coords = coords, h = h }
    save()
    refresh(id)
    TriggerClientEvent('norte_bancada:client:add', -1, packMachine(id))
    exports.whip_core:NotifyPlayer(source, 'Machine placed', 'success')
    return true
end

--- Tira a máquina do mundo. Com `source`, o que tem dentro e a própria máquina vão para os bolsos dele, e recusa
--- se não couber. Sem `source` (a consola), o contentor é apagado com o que tiver dentro.
local function removeMachine(id, source)
    if source then
        local _, whyAmmo = takeSide(source, id, 'ammo')
        local _, whyMags = takeSide(source, id, 'mags')
        local contents = Whip.core:StoreRead(storeOf(id))
        if not contents then return false, 'Could not open the machine' end
        if next(contents.items or {}) then
            refresh(id)
            return false, whyAmmo or whyMags or 'No room in your pockets for what is in the machine'
        end
    end

    local kind = Machines[id] and Machines[id].kind or Config.DefaultType
    local ok, why = Whip.core:DeleteContainer(id)
    if not ok and Whip.core:GetContainer(id) then return false, why end
    Machines[id], sent[id], jobs[id] = nil, nil, nil
    save()
    TriggerClientEvent('norte_bancada:client:remove', -1, id)
    if source then Whip.core:AddItem(source, kind, 1, nil, 'norte_bancada: guardada') end
    return true
end

--- Guarda a máquina: o que tem dentro volta para os bolsos, e a máquina volta a ser um item.
local function pickup(source, player, id)
    local m = Machines[id]
    if not m then return false, 'That machine is gone' end
    if m.owner ~= player.charId then return false, 'This machine is not yours' end
    if jobs[id] then return false, 'The machine is running' end
    local ok, why = removeMachine(id, source)
    if not ok then return false, why end
    exports.whip_core:NotifyPlayer(source, 'Machine packed up', 'success')
    return true
end

-- ===================================================================================================
-- Declarações
-- ===================================================================================================

Whip.register(function()
    if not loadGunny() then
        warn('sem os dados do whip_gunny a máquina não arranca')
        return
    end

    -- Um item por tipo de máquina. Usar o item só abre a colocação no cliente; o item sai quando o servidor aceita
    -- o sítio (norte_bancada:place).
    local kinds = {}
    for kind, T in pairs(Config.Types) do
        kinds[#kinds + 1] = kind
        Whip.core:RegisterItem(kind, {
            name = T.label, desc = T.desc,
            weight = T.weight, type = 'tool', stack = false, usable = true, prop = T.model,
        })
        Whip.core:RegisterUseHandler(kind, function(source)
            TriggerClientEvent('norte_bancada:client:place', source, kind)
            return false
        end)
    end

    Whip.core:SecureEvent('norte_bancada:place', {
        rateLimit = 2000,
        params = {
            { 'kind', 'enum', kinds },
            { 'x', 'number', -10000.0, 10000.0 },
            { 'y', 'number', -10000.0, 10000.0 },
            { 'z', 'number', -500.0, 2000.0 },
            { 'h', 'number', 0.0, 360.0 },
        },
    }, function(source, player, kind, x, y, z, h)
        return guarded(source, place, source, player, kind, x, y, z, h)
    end)

    Whip.core:SecureEvent('norte_bancada:put', {
        rateLimit = 1000,
        params = {
            { 'id', 'id' },
            { 'side', 'enum', { 'ammo', 'mags' } },
            { 'item', 'key', 60 },
            { 'amount', 'amount', 9999 },
            { 'slot', 'int', 0, 12, 0 },   -- o slot da MK2; 0 na máquina de 3
        },
    }, function(source, player, id, side, item, amount, slot)
        local _, why = nearMachine(source, id)
        if why then return false, why end
        local ok, err = guarded(source, put, source, player, id, side, item, amount, slot or 0)
        refresh(id)
        if not ok then return false, err end
    end)

    Whip.core:SecureEvent('norte_bancada:take', {
        rateLimit = 750,
        params = {
            { 'id', 'id' },
            { 'side', 'enum', { 'ammo', 'mags' } },
            { 'slot', 'int', 0, 12, 0 },   -- só os carregadores deste slot da MK2; 0: todos
        },
    }, function(source, _, id, side, slot)
        local _, why = nearMachine(source, id)
        if why then return false, why end
        local ok, err = guarded(source, take, source, id, side, slot or 0)
        refresh(id)
        if not ok then return false, err end
    end)

    Whip.core:SecureEvent('norte_bancada:stop', {
        rateLimit = 1000,
        params = { { 'id', 'id' } },
    }, function(source, _, id)
        local _, why = nearMachine(source, id)
        if why then return false, why end
        return guarded(source, stop, source, id)
    end)

    Whip.core:SecureEvent('norte_bancada:start', {
        rateLimit = 1000,
        params = { { 'id', 'id' } },
    }, function(source, player, id)
        local _, why = nearMachine(source, id)
        if why then return false, why end
        return guarded(source, start, source, player, id)
    end)

    Whip.core:SecureEvent('norte_bancada:pickup', {
        rateLimit = 2000,
        params = { { 'id', 'id' } },
    }, function(source, player, id)
        local _, why = nearMachine(source, id)
        if why then return false, why end
        return guarded(source, pickup, source, player, id)
    end)

    Whip.core:SecureCallback('norte_bancada:pockets', {
        rateLimit = 400, burst = 3,
        params = {
            { 'id', 'id' },
            { 'side', 'enum', { 'ammo', 'mags' } },
        },
    }, function(source, _, id, side)
        local _, why = nearMachine(source, id)
        if why then return false, why end
        return pocketList(source, side)
    end)

    Whip.core:SecureCallback('norte_bancada:list', {
        rateLimit = 2000, burst = 2, requirePlayer = false,
    }, function()
        local list = {}
        for id in pairs(Machines) do list[#list + 1] = packMachine(id) end
        return list
    end)

    -- As máquinas guardadas: as que o WHIP ainda tem como contentor voltam, trancadas.
    CreateThread(function()
        Machines, jobs, sent = {}, {}, {}
        local dropped = false
        for _, row in ipairs(loadSaved()) do
            local id = math.tointeger(tonumber(row.id))
            local def = id and Whip.core:GetContainer(id)
            if def then
                local kind = Config.Types[row.kind] and row.kind or Config.DefaultType
                Machines[id] = { id = id, kind = kind, owner = row.owner,
                    coords = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0), h = row.h or 0.0 }
                if not def.locked then Whip.core:UpdateContainer(id, { locked = true }) end
            else
                dropped = true
            end
        end
        if dropped then save() end
        for id in pairs(Machines) do refresh(id) end
        local list = {}
        for id in pairs(Machines) do list[#list + 1] = packMachine(id) end
        TriggerClientEvent('norte_bancada:client:all', -1, list)
    end)
end)

-- Admin: /bancada_remove tira a máquina mais perto (até 5 m), seja de quem for, e dá-lhe o conteúdo e a máquina.
-- Na consola, `bancada_remove all` apaga todas as máquinas e o que têm dentro.
Whip.command('bancada_remove', { ace = 'whip.devtools' }, function(source, args)
    if source == 0 then
        if args[1] ~= 'all' then
            print('[norte_bancada] console usage: bancada_remove all (deletes every machine and what is inside)')
            return
        end
        local n = 0
        for id in pairs(Machines) do
            if removeMachine(id) then n = n + 1 end
        end
        print(('[norte_bancada] %d machine(s) removed'):format(n))
        return
    end

    local ped = GetPlayerPed(source)
    local pos = ped ~= 0 and GetEntityCoords(ped)
    local best, bestDist
    for id, m in pairs(Machines) do
        local d = pos and #(pos - m.coords)
        if d and d <= 5.0 and (not bestDist or d < bestDist) then best, bestDist = id, d end
    end
    if not best then
        Whip.core:NotifyPlayer(source, 'No machine within 5 m', 'error')
        return
    end
    local ok, why = removeMachine(best, source)
    Whip.core:NotifyPlayer(source, ok and 'Machine removed' or why, ok and 'success' or 'error')
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)
