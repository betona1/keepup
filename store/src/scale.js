// 창 크기에 맞춰 1080x1920 캔버스를 확대하고 가운데 정렬한다 (태블릿 렌더용)
addEventListener('load', () => {
  const s = Math.min(innerWidth / 1080, innerHeight / 1920);
  const b = document.body.style;
  b.transform = `scale(${s})`;
  b.marginLeft = ((innerWidth - 1080 * s) / 2) + 'px';
  b.marginTop = ((innerHeight - 1920 * s) / 2) + 'px';
});
