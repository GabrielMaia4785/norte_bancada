// norte_bancada: o ecrã da MK2. Só mostra o estado que client.lua manda (SendDuiMessage); o servidor conta as balas.
(() => {
    const SEGMENTS = 20;
    const screen = document.getElementById('screen');
    const status = document.getElementById('status');
    const pct = document.getElementById('pct');
    const count = document.getElementById('count');
    const mag = document.getElementById('mag');
    const rounds = document.getElementById('rounds');
    const holder = document.getElementById('segments');
    const title = document.getElementById('title');

    const segs = [];
    for (let i = 0; i < SEGMENTS; i++) {
        const s = document.createElement('i');
        s.className = 'segment';
        holder.appendChild(s);
        segs.push(s);
    }

    const pad = (n) => String(Math.max(0, n | 0)).padStart(3, '0');

    function render(d) {
        const total = Math.max(0, Number(d.total) || 0);
        const loaded = Math.min(total, Math.max(0, Number(d.loaded) || 0));
        const ratio = total > 0 ? loaded / total : 0;
        const state = d.working ? 'loading' : (d.done ? 'done' : 'idle');

        if (d.title) title.textContent = d.title;
        screen.dataset.state = state;
        status.textContent = state === 'loading' ? 'LOADING' : state === 'done' ? 'COMPLETE' : 'STANDBY';
        pct.textContent = `${Math.round(ratio * 100)}%`;
        count.textContent = `${pad(loaded)} / ${pad(total)} RDS`;
        const lit = Math.round(ratio * SEGMENTS);
        segs.forEach((s, i) => s.classList.toggle('is-on', i < lit));

        const mags = Number(d.mags) || 0;
        mag.textContent = mags > 0 ? `${d.magLabel || 'MAGAZINE'} · ${Number(d.full) || 0}/${mags} FULL` : 'NO MAGAZINES';
        rounds.textContent = `${Number(d.rounds) || 0} RDS IN HOPPER`;
    }

    window.addEventListener('message', (e) => {
        let d = e.data;
        if (typeof d === 'string') { try { d = JSON.parse(d); } catch (_) { return; } }
        if (d && d.action === 'state') render(d);
    });

    render({});

    // Pré-visualização fora do FiveM: abre html/screen.html num browser.
    if (!window.invokeNative) {
        let loaded = 0;
        const total = 144;
        setInterval(() => {
            loaded = loaded >= total ? 0 : Math.min(total, loaded + 12);
            render({ working: loaded < total, done: loaded >= total, loaded, total, mags: 12,
                full: Math.floor(loaded / 12), magLabel: 'Pistol Magazine', rounds: 300 - loaded });
        }, 900);
    }
})();
