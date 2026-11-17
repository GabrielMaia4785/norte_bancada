-- Encaixes da máquina MK2 (nr_bancada_mk2_municoes), do pacote original norte_bancada_mk2.
-- 4 apoios (indice 1 a 4) com 3 lugares cada (lugar 1 a 3): 12 carregadores. A caixa fica no topo esquerdo.
-- Offsets locais para AttachEntityToEntity, rotationOrder 2. Devolve nil se o objeto não couber ou o modelo não
-- estiver carregado.
local slots = { -0.144, 0.136, 0.416, 0.696 }
local lugares = { -0.078, 0, 0.078 }
local function getApoio(modelo, posto, indice, lugar)
    local x = slots[indice or 1]
    if posto == 'carregador' then
        local offset = lugares[lugar or 2]
        if not x or not offset then return nil end
        x = x + offset
    end
    if posto ~= 'caixa' and posto ~= 'carregador' then return nil end
    local hash = type(modelo) == 'string' and joaat(modelo) or modelo
    if not hash or not HasModelLoaded(hash) then return nil end
    local a,b = GetModelDimensions(hash)
    local d,c = b-a,(a+b)*0.5
    if math.min(d.x,d.y,d.z) <= 0 then return nil end
    if posto == 'caixa' then
        if d.x <= .354 and d.y <= .245 then
            return {pos=vector3(-.474-c.x,c.y,.553+b.z),rot=vector3(180,0,0)}
        elseif d.y <= .354 and d.x <= .245 then
            return {pos=vector3(-.474+c.y,c.x,.553+b.z),rot=vector3(0,180,90)}
        end
    elseif d.z <= .280 then
        if d.x <= .072 and d.y <= .222 then
            return {pos=vector3(x-c.x,-.020-c.y,.386-b.z),rot=vector3(0,0,0)}
        elseif d.y <= .072 and d.x <= .222 then
            return {pos=vector3(x+c.y,-.020-c.x,.386-b.z),rot=vector3(0,0,90)}
        end
    end
end
exports('getApoioMk2', getApoio)
