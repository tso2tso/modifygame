# UI 素材生成清单与 Prompt

本文档用于后续生成并接入首页与通用 UI 素材。当前 Lua UI 侧尚未确认稳定的图片控件 API，因此本轮先保留 emoji 占位，通过布局、色彩和卡片层级提升精致度；素材生成后再接入事件卡、矿山焦点卡、底部导航和资源栏。

## 总体美术方向

- 风格关键词：工业帝国主义、巴尔干矿业家族、旧账簿、铜版画、暗金边框、煤黑皮革、旧羊皮纸。
- 色彩限制：深煤黑 `#1A1814`、深棕 `#242018`、旧金 `#C9A84C`、羊皮纸白 `#F0E6D0`、低饱和红绿蓝。
- 避免内容：现代霓虹、Q版卡通、过亮赛博风、塑料质感、过多纯黑、文字水印。
- 透明图标建议导出 PNG，插画和纹理建议 WebP 或 PNG。

## 资源图标

尺寸建议：64x64，透明背景，适配顶栏和本季概览。

通用 prompt：

```text
Create a 64x64 transparent PNG game UI icon in a dark historical ledger style, Balkan mining dynasty theme, low saturation brass and parchment colors, subtle copper engraving lines, readable at small size, no text, no watermark, no modern neon, no cartoon exaggeration.
```

单项补充：

- 现金：old Austro-Hungarian money pouch and coins, brass highlights.
- 黄金：single gold ore nugget, muted shine, engraved outline.
- 产能：crossed pickaxe and small gear, industrial mining symbol.
- 声望：small brass star medal, old family prestige emblem.
- 净资产：bank ledger building silhouette with coin stack.
- AP：round action seal, brass rim, parchment center, no letters.

## 底部导航图标

尺寸建议：80x80，透明背景，统一线宽。需要生成 5 个普通态和 5 个高亮态；高亮态使用更明显旧金描边。

基础 prompt：

```text
Create an 80x80 transparent PNG mobile game navigation icon, dark Balkan industrial dynasty ledger style, brass line art, parchment highlights, subtle engraved texture, centered composition, no text, no watermark, readable at 32px.
```

图标主题：

- 家族：two old family silhouettes with small crest.
- 产业：mine entrance with pickaxe.
- 市场：ledger chart with coin.
- 武装：shield with crossed rifle silhouettes, historical not modern tactical.
- 世界：old map globe with compass mark.

## 首页矿山焦点图

尺寸建议：128x96 或 192x144。用于首页焦点卡左侧资产图，可先生成 2x 分辨率再缩放。

prompt：

```text
Dark historical game UI asset illustration of a Balkan gold mine entrance in 1904, timber supports, oil lamp, rough stone, faint warm brass light, old ledger and copper engraving aesthetic, low saturation brown black and antique gold palette, compact composition for a mobile card, no characters, no text, no watermark, not cartoon, not photorealistic, no modern machinery.
```

可选变体：

- early mine: hand tools, wooden supports, oil lamp.
- industrial mine: steam drill, rail cart, coal smoke.
- modern mine: deeper shaft, subtle electric light, still historical and grounded.

## 事件插画

尺寸建议：160x100 或 128x80。用于事件卡左图，按类别复用。

通用 prompt：

```text
Small historical event illustration for a mobile strategy game UI, Sarajevo and Balkan mining dynasty theme, old ledger page and copperplate engraving style, dark brown parchment palette with muted brass accent, dramatic but readable at small size, no text, no watermark, no modern neon, no cartoon.
```

类别补充：

- 矿权事件：sealed mining concession document, pickaxe, wax seal, mountain mine in background.
- 铁路/基建：narrow gauge railway entering a mining valley, survey tools, old map.
- 工人事件：workers barracks and mine lamps, tense but non-violent.
- 战争动员：distant soldiers and rail depot, dark red undertone, no gore.
- 金融危机：ledger book, falling coins, cracked market chart, muted red accent.
- 政治改革：government building silhouette, papers, seal, restrained blue accent.

## 卡片与背景纹理

尺寸建议：512x512 可平铺纹理。

煤黑皮革背景：

```text
Seamless 512x512 dark coal-black leather and soot texture for a mobile game UI background, subtle grain, very low contrast, historical ledger mood, no symbols, no text, no bright highlights, tileable.
```

旧羊皮纸内嵌面板：

```text
Seamless 512x512 aged parchment texture, dark sepia brown, subtle paper fibers, low contrast, suitable for dark UI panels, no text, no stains that distract, tileable.
```

暗金边框素材：

```text
Thin antique brass ornamental border for a mobile strategy game UI card, Balkan imperial ledger style, subtle copper engraving, low saturation gold, transparent background, no text, no watermark, designed to frame dark brown cards.
```

## 接入建议

1. 优先接入矿山焦点图和事件插画，因为它们能最快替代首页最明显的 emoji 占位。
2. 第二批接入底部导航图标和资源图标，统一顶栏、导航和概览区的视觉语言。
3. 最后接入可平铺纹理，避免过早引入性能或可读性问题。
4. 所有素材导入前先做 32px、48px、64px 小尺寸预览，确认不糊、不脏、不抢文字层级。
