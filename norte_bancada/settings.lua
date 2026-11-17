-- norte_bancada — a página em /whip → Settings → Magazine Loader
--
-- Os valores de config.lua são os de origem. Um admin muda-os no painel, o WHIP guarda-os na base de dados e
-- escreve-os no Config dos dois lados. O código lê Config a cada uso, por isso a mudança vale logo.

-- Um ponto do prompt no referencial da máquina: metros à volta dela e o heading em graus.
local POINT = { x = { -2, 2 }, y = { -2, 2 }, z = { -1, 3 }, w = { 0, 360 } }

Whip.configPage({
    label = 'Magazine Loader',
    groups = {
        { label = 'Loading', settings = {
            { key = 'MsPerRound', type = 'int', min = 20, max = 5000, step = 10, unit = 'ms',
              label = 'Time per round',
              help = 'How long the machine takes to load one round. Loading by hand in whip_gunny is 300 ms.' },
            { key = 'Types.norte_bancada.maxMags', type = 'int', min = 1, max = 3, step = 1,
              label = 'Magazines per machine',
              help = 'How many magazines the Magazine Loader takes at once. It has room for 3.' },
        } },
        { label = 'Prompt', settings = {
            { key = 'PromptSide', type = 'enum', label = 'Side of the machine',
              help = 'Which face the prompt stands on. Right is the magazine side.',
              options = {
                  { value = 'right', label = 'Right' }, { value = 'left', label = 'Left' },
                  { value = 'front', label = 'Front' }, { value = 'back', label = 'Back' },
              } },
            { key = 'Types.norte_bancada.promptPlaced', type = 'bool', label = 'Placed by hand',
              help = 'On: the Magazine Loader\'s prompt stands at its Prompt point below, and Side, Height and Distance do not apply to it.' },
            { key = 'Types.norte_bancada.promptPoint', type = 'vec4', label = 'Prompt point',
              limits = POINT, axisLabels = { 'Across', 'Out front', 'Up', 'Heading' },
              help = 'Relative to the machine: metres across, out of its front and up, and the heading from its own (180 faces back). Measure it with /int nr_bancada_municoes and copy the numbers here.' },
            { key = 'Types.norte_bancada_mk2.promptPlaced', type = 'bool', label = 'Placed by hand (MK2)',
              help = 'The same for the Magazine Loader MK2.' },
            { key = 'Types.norte_bancada_mk2.promptPoint', type = 'vec4', label = 'Prompt point (MK2)',
              limits = POINT, axisLabels = { 'Across', 'Out front', 'Up', 'Heading' },
              help = 'The same for the Magazine Loader MK2: measure it with /int nr_bancada_mk2_municoes.' },
            { key = 'PromptHeight', type = 'number', min = 0, max = 1.5, step = 0.05,
              label = 'Height on the side', help = '0 is the base, 1 is the top of the machine.' },
            { key = 'PromptGap', type = 'number', min = 0, max = 0.5, step = 0.01, unit = 'm',
              label = 'Distance from the face' },
            { key = 'PromptScale', type = 'number', min = 0.25, max = 2, step = 0.05,
              label = 'Prompt size', help = '1 is the normal size of WHIP prompts.' },
        } },
        { label = 'Sound', settings = {
            { key = 'SoundVolume', type = 'number', min = 0, max = 1, step = 0.05,
              label = 'Volume next to the machine', help = '0 is silent, 1 is full volume.' },
            { key = 'SoundRange', type = 'number', min = 2, max = 50, step = 1, unit = 'm',
              label = 'Heard up to' },
        } },
    },
})
