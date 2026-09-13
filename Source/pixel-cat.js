// A decorative companion, entirely local. Pixel sprites are drawn at native resolution.
(() => {
  const clock = document.querySelector('.time');
  const baseline = document.createElement('span');
  baseline.className = 'cat-baseline';
  baseline.setAttribute('aria-hidden', 'true');
  clock.append(baseline);

  const canvas = document.createElement('canvas');
  canvas.width = 32; canvas.height = 28;
  canvas.className = 'pixel-cat';
  canvas.setAttribute('aria-hidden', 'true');
  canvas.title = 'Pick me up and drop me somewhere';
  document.body.append(canvas);
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  const measure = document.createElement('canvas').getContext('2d');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const settings = document.querySelector('#pomodoro-settings');
  const palette = { o:'#493a32', f:'#d6aa78', h:'#f6dfb6', s:'#b77f50', p:'#deaaa0', e:'#302c29' };
  const sprites = {
    sit: [
      '       oo      oo      ',
      '       ofo    ofo      ',
      '       ofpoooopfo      ',
      '       ofhffffhfo      ',
      '      ofhhhhhhhfo      ',
      '      ohhehhhehho      ',
      '      ohhhphhhhho      ',
      '       ohhhhhho       ',
      '        offhfo        ',
      '       offsfffo       ',
      '       offhfffo       ',
      '      offhhhfffo      ',
      '      offhhhfffo      ',
      '   oo offhhhfffo      ',
      '  ofo offhhhfffo      ',
      '  ofo offhfhfffo      ',
      '  offooffhfhfffo      ',
      '   offfffhfhffo       ',
      '    ooohhhohhho       ',
      '       ooo ooo        '
    ],
    held: [
      '       oo      oo      ',
      '       ofo    ofo      ',
      '       ofpoooopfo      ',
      '       ofhffffhfo      ',
      '      ofhhhhhhhfo      ',
      '      ohhehhhehho      ',
      '      ohhhphhhhho      ',
      '       ohhhhhho       ',
      '        offhfo        ',
      '       offsfffo       ',
      '      offhhhfffo      ',
      '      ofohhhfofo      ',
      '      ohohhhoho       ',
      '       oohhhoo        ',
      '        ohhho         ',
      '     oo offhfo        ',
      '     ofooffhfo        ',
      '      offhfhfo        ',
      '       ofo ofo        ',
      '       ofo ofo        ',
      '       oho oho        ',
      '       ooo ooo        '
    ],
    walk: [
      '                oo   oo ',
      '                ofo ofo ',
      '                ofpoofo ',
      '               ofhhfffo ',
      '  oo           ohhhehho ',
      ' ofo  ooooooooofhhhhpho ',
      ' ofo offssffssfhhhhhhho ',
      ' ofooffffffffffhhhhho  ',
      '  offffffffffffhhfoo   ',
      '   ooffffffffffhhfo    ',
      '     offhhhhhhhhffo    ',
      '     offhoooooffffo    ',
      '     offo     offo     ',
      '     ohho     ohho     ',
      '     oooo     oooo     '
    ],
    step: [
      '                oo   oo ',
      '                ofo ofo ',
      '                ofpoofo ',
      '               ofhhfffo ',
      '  oo           ohhhehho ',
      ' ofo  ooooooooofhhhhpho ',
      ' ofo offssffssfhhhhhhho ',
      ' ofooffffffffffhhhhho  ',
      '  offffffffffffhhfoo   ',
      '   ooffffffffffhhfo    ',
      '     offhhhhhhhhffo    ',
      '      offoooooffo      ',
      '       ofo   ofo       ',
      '       ohho  ohho      ',
      '       oooo  oooo      '
    ],
    jump: [
      '                 oo  oo ',
      '                 ofo ofo',
      '                 ofpoofo',
      '                ofhhfffo',
      ' oo    ooooooooofhhhehho',
      ' ofo ooffssffssffhhhhpho',
      '  ofofffffffffffhhhhhho',
      '   offffffffffffhhhhho ',
      '    offhhhhhhhhhhffoo  ',
      '    offhoooooooffffo   ',
      '     ohho      ohho    ',
      '      oo        oo     '
    ],
    sleep: [
      '        ooooooo        ',
      '      ooffssfffoo      ',
      '  oo oofffffffffoo     ',
      '  ofooffffffffhffoo    ',
      '  ofhfffhhhhhhhhhfo    ',
      ' ofhhhhfhhhhhhhhhhfo   ',
      ' ohheephhhfffffffhfo   ',
      '  ohhhhhffffssssfffo   ',
      '   oohhffffffffffoo    ',
      '     oooooooooooo      '
    ]
  };
  const random = (low, high) => low + Math.random() * (high - low);
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  let anchor = { surface:'clock', u:.18 };
  let journey = null, pose = 'sit', facing = 1, nextAction = 0, excursions = 0, hasMoved = false;
  let activeTime = 0, previousTime = 0, followUntil = 0, timer = 0, frame = 0;
  let lastSprite = '', lastTransform = '', scale = 2;
  let geometry = null, drag = null, displayedPosition = null;

  function readGeometry() {
    scale = (innerWidth < 600 || innerHeight < 360 ? 1 : innerWidth >= 1600 ? 3 : 2) * 1.25;
    const style = getComputedStyle(clock);
    measure.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const clockRect = clock.getBoundingClientRect();
    const zoom = clock.offsetWidth ? clockRect.width / clock.offsetWidth : 1;
    // Measure the baseline rather than the line box so paws rest on the ink.
    const baselineY = baseline.getBoundingClientRect().top;
    const platforms = [...clock.querySelectorAll('.rn-token, .sep')]
      .filter(digit => digit.getBoundingClientRect().width > 0)
      .map(digit => {
        const rect = digit.getBoundingClientRect();
        const glyph = digit.textContent === ':' ? ':' : '0';
        const top = baselineY - measure.measureText(glyph).actualBoundingBoxAscent * zoom;
        return { x:rect.left + rect.width / 2, width:rect.width, top };
      });
    geometry = { platforms };
    canvas.style.width = `${32 * scale}px`;
    canvas.style.height = `${28 * scale}px`;
  }

  function point(at) {
    const { platforms } = geometry;
    if (at.surface === 'air') return { x:innerWidth * at.u, y:innerHeight * at.v };
    if (at.surface === 'floor' || platforms.length === 0) {
      return { x:innerWidth * at.u, y:innerHeight - 12 };
    }
    // Coordinates refer to a digit or colon, so resize and the hour appearing cannot strand the cat.
    const position = clamp(at.u, 0, .999) * platforms.length;
    const digit = platforms[Math.floor(position)];
    const across = (position % 1 - .5) * digit.width * .4;
    return { x:digit.x + across, y:Math.max(28 * scale + 8, digit.top + Math.abs(across) * .12) };
  }

  function drawSprite(name, blink) {
    const signature = `${name}:${facing}:${blink}`;
    if (signature === lastSprite) return;
    lastSprite = signature;
    ctx.clearRect(0, 0, 32, 28);
    ctx.save();
    if (facing < 0) { ctx.translate(32, 0); ctx.scale(-1, 1); }
    const sprite = sprites[name];
    const offsetY = 26 - sprite.length;
    sprite.forEach((row, y) => [...row].forEach((pixel, x) => {
      if (!palette[pixel]) return;
      ctx.fillStyle = blink && pixel === 'e' ? palette.s : palette[pixel];
      ctx.fillRect(x + 3, y + offsetY, 1, 1);
    }));
    if (name === 'sleep') {
      // A single quiet, stationary pixel z.
      ctx.fillStyle = '#f6dfb699';
      [[24,9],[25,9],[26,9],[25,10],[24,11],[25,11],[26,11]].forEach(([x,y]) => ctx.fillRect(x,y,1,1));
    }
    ctx.restore();
  }

  function rest(now, nap = false) {
    pose = nap ? 'sleep' : 'sit';
    const running = document.querySelector('#toggle').dataset.icon === 'pause';
    nextAction = now + (nap ? random(running ? 30000 : 18000, running ? 55000 : 35000) : random(4500, 8500));
  }

  function chooseAction(now) {
    if (pose === 'sleep') { rest(now); return; }
    if (hasMoved && (excursions >= 2 || Math.random() < .3)) {
      excursions = 0; rest(now, true); return;
    }
    let target;
    if (anchor.surface === 'floor') {
      target = { surface:'clock', u:anchor.u < .5 ? .12 : .88 };
    } else if (innerWidth > 600 && Math.random() < .18) {
      // Screen-edge trips are rare; the middle of the control row stays clear.
      target = { surface:'floor', u:anchor.u < .5 ? .08 : .92 };
    } else {
      const count = geometry.platforms.length || 4;
      const digit = Math.min(count - 1, Math.floor(anchor.u * count));
      const direction = digit === 0 ? 1 : digit === count - 1 ? -1 : Math.random() < .5 ? -1 : 1;
      const nextDigit = Math.random() < .3 ? digit : digit + direction;
      target = { surface:'clock', u:(clamp(nextDigit, 0, count - 1) + random(.3, .7)) / count };
    }
    const from = point(anchor), to = point(target);
    const walk = anchor.surface === target.surface && Math.abs(from.x - to.x) < (geometry.platforms[0]?.width || 80) * .5;
    facing = to.x >= from.x ? 1 : -1;
    const distance = Math.hypot(to.x - from.x, to.y - from.y);
    journey = { from:anchor, to:target, start:now, duration:walk ? clamp(distance / 20 * 1000, 1300, 2600) : clamp(distance / 220 * 1000, 950, 2500), walk };
    excursions++; hasMoved = true;
  }

  function update(timestamp) {
    frame = 0; timer = 0;
    const delta = previousTime ? Math.min(1000, timestamp - previousTime) : 0;
    previousTime = timestamp;
    if (!geometry || timestamp < followUntil) readGeometry();
    const paused = document.hidden || settings.open;
    if (!paused) activeTime += delta;
    if (reduceMotion.matches && !drag) { journey = null; pose = 'sleep'; }
    else if (!paused && !drag && !journey && activeTime >= nextAction) chooseAction(activeTime);
    let position = point(anchor), sprite = pose;
    if (journey) {
      const progress = clamp((activeTime - journey.start) / journey.duration, 0, 1);
      const start = point(journey.from), end = point(journey.to);
      const eased = journey.drop ? progress * progress : progress * progress * (3 - 2 * progress);
      const arc = journey.walk || journey.drop ? 0 : Math.min(100, innerHeight * .1) * Math.sin(Math.PI * progress);
      position = { x:start.x + (end.x - start.x) * eased, y:start.y + (end.y - start.y) * eased - arc };
      sprite = journey.walk ? (Math.floor(activeTime / 190) % 2 ? 'walk' : 'step') : 'jump';
      if (progress === 1) {
        const dropped = journey.drop;
        anchor = journey.to; journey = null; rest(activeTime);
        if (dropped) nextAction = activeTime + 15000;
        sprite = pose;
      }
    }
    if (drag) { position = drag.position; sprite = 'held'; }
    paint(position, sprite);
    if (document.hidden) return;
    const moving = !paused && journey && !reduceMotion.matches;
    // Resting costs only two small checks a second; smooth frames only during a hop or resize.
    timer = setTimeout(() => { frame = requestAnimationFrame(update); }, moving || timestamp < followUntil ? 32 : 500);
  }

  function paint(position, sprite) {
    const x = Math.round(clamp(position.x - 16 * scale, 4, innerWidth - 32 * scale - 4));
    const y = Math.round(clamp(position.y - 26 * scale, 4, innerHeight - 28 * scale - 4));
    displayedPosition = { x:x + 16 * scale, y:y + 26 * scale };
    const transform = `translate(${x}px,${y}px)`;
    if (transform !== lastTransform) { canvas.style.transform = transform; lastTransform = transform; }
    canvas.dataset.pose = sprite;
    drawSprite(sprite, !reduceMotion.matches && pose === 'sit' && activeTime % 8000 > 7760);
  }

  function moveDrag(event) {
    if (!drag || event.pointerId !== drag.pointerId) return;
    drag.position = { x:event.clientX + (16 - drag.grabX * 32) * scale, y:event.clientY + (26 - drag.grabY * 28) * scale };
    paint(drag.position, 'held');
  }

  function finishDrag(immediate = false) {
    if (!drag) return;
    const pointerId = drag.pointerId;
    const released = displayedPosition;
    drag = null; delete canvas.dataset.dragging;
    if (canvas.hasPointerCapture(pointerId)) canvas.releasePointerCapture(pointerId);
    readGeometry();
    let target = { surface:'floor', u:clamp(released.x / innerWidth, 0, 1) };
    // Only catch a digit or colon if the cat is above it. Dropping below the clock falls to the floor.
    geometry.platforms.some((digit, index) => {
      if (Math.abs(released.x - digit.x) > digit.width * .45) return false;
      const within = clamp((released.x - digit.x) / (digit.width * .4), -.49, .49) + .5;
      const candidate = { surface:'clock', u:(index + within) / geometry.platforms.length };
      if (released.y > point(candidate).y + 6 * scale) return false;
      target = candidate; return true;
    });
    anchor = target;
    rest(activeTime, reduceMotion.matches);
    nextAction = activeTime + 15000;
    excursions = 0; hasMoved = true;
    if (!immediate && !reduceMotion.matches) {
      const distance = Math.hypot(point(target).x - released.x, point(target).y - released.y);
      journey = { from:{ surface:'air', u:released.x / innerWidth, v:released.y / innerHeight }, to:target, start:activeTime, duration:clamp(Math.sqrt(distance / 700) * 1000, 220, 1100), drop:true };
    } else journey = null;
    refresh();
  }

  canvas.addEventListener('pointerdown', event => {
    if (event.button !== 0 || event.isPrimary === false || settings.open || drag) return;
    event.preventDefault();
    readGeometry();
    const rect = canvas.getBoundingClientRect();
    drag = { pointerId:event.pointerId, grabX:(event.clientX - rect.left) / rect.width, grabY:(event.clientY - rect.top) / rect.height, position:displayedPosition || point(anchor) };
    journey = null; canvas.dataset.dragging = 'true';
    canvas.setPointerCapture(event.pointerId);
    paint(drag.position, 'held');
  });
  canvas.addEventListener('pointermove', moveDrag);
  canvas.addEventListener('pointerup', event => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    moveDrag(event); finishDrag();
  });
  canvas.addEventListener('pointercancel', () => finishDrag(true));
  canvas.addEventListener('lostpointercapture', () => finishDrag(true));
  canvas.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); });
  window.addEventListener('blur', () => finishDrag(true));

  function refresh() {
    followUntil = performance.now() + 1850;
    cancelAnimationFrame(frame); clearTimeout(timer);
    frame = requestAnimationFrame(update);
  }
  new ResizeObserver(refresh).observe(clock);
  let wasIdle = document.body.classList.contains('idle');
  new MutationObserver(() => {
    const idle = document.body.classList.contains('idle');
    if (idle !== wasIdle) { wasIdle = idle; refresh(); }
  }).observe(document.body, { attributes:true, attributeFilter:['class'] });
  // Opening a modal pauses the cat, but never pauses or alters the actual timer.
  new MutationObserver(() => { if (settings.open) finishDrag(true); refresh(); }).observe(settings, { attributes:true, attributeFilter:['open'] });
  window.addEventListener('resize', refresh);
  document.addEventListener('visibilitychange', () => { if (document.hidden) finishDrag(true); previousTime = 0; refresh(); });
  reduceMotion.addEventListener('change', () => { rest(activeTime, true); refresh(); });
  document.fonts.ready.then(() => { rest(0); refresh(); });
})();
