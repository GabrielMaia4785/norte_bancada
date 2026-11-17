local function getApoio(modelo, posto)
    if posto ~= 'caixa' and posto ~= 'carregador' then return nil end
    local hash = type(modelo) == 'string' and joaat(modelo) or modelo
    if not hash or not HasModelLoaded(hash) then return nil end
    local a,b = GetModelDimensions(hash)
    local d,c = b-a,(a+b)*0.5
    if math.min(d.x,d.y,d.z) <= 0 then return nil end
    if posto == 'caixa' then
        if d.x <= .354 and d.y <= .245 then
            return {pos=vector3(-.165-c.x,c.y,.406+b.z),rot=vector3(180,0,0)}
        elseif d.y <= .354 and d.x <= .245 then
            return {pos=vector3(-.165+c.y,c.x,.406+b.z),rot=vector3(0,180,90)}
        end
    elseif d.z <= .238 then
        if d.x <= .190 and d.y <= .222 then
            return {pos=vector3(.252-c.x,-c.y,.320-b.z),rot=vector3(0,0,0)}
        elseif d.y <= .190 and d.x <= .222 then
            return {pos=vector3(.252+c.y,-c.x,.320-b.z),rot=vector3(0,0,90)}
        end
    end
end
exports('getApoio', getApoio)
