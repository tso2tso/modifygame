-- works_lore.lua
-- 作品历史典故与立绘数据
-- 对应游戏中的电影、史诗、剧团三类文化作品

local WorksLore = {}

-- ============================================================
-- 电影题材典故
-- ============================================================
WorksLore.FILM = {
    historical = {
        title        = "《萨拉热窝往事》",
        subtitle     = "历史题材 · 1903年",
        desc         = "以1878年柏林会议为背景，再现奥匈帝国接管波斯尼亚的历史转折。影片通过一名萨拉热窝老翻译的视角，展现了那个时代的权力更迭与民间百态。上映后引发广泛共鸣，成为萨拉热窝人谈论最多的本土电影。",
        flavor       = "「历史不会重演，但总会押韵。」——萨拉热窝剧评人语",
        portraitImage = "image/works/film_historical.png",
        icon         = "🎞️",
    },
    national = {
        title        = "《萨拉热窝之魂》",
        subtitle     = "民族题材 · 1905年",
        desc         = "一部描绘波斯尼亚民族觉醒的史诗级影片。影片以真实的民间传说为蓝本，讲述了英雄哈伊鲁丁守护家园的故事。尽管奥匈当局对其政治倾向保持警惕，但影片仍在民间引发强烈反响，成为本地民族运动的精神符号之一。",
        flavor       = "「土地是脚下的，灵魂是心里的。」——剧中台词",
        portraitImage = "image/works/film_national.png",
        icon         = "🎞️",
    },
    industrial = {
        title        = "《地底之光》",
        subtitle     = "工业题材 · 1906年",
        desc         = "以波斯尼亚煤矿工人为主角，记录了工业化浪潮下普通人的生活与抗争。影片大量取景于真实矿场，展示了工人的日常劳作与危险处境，被誉为「波斯尼亚第一部社会现实主义电影」。",
        flavor       = "「机器在轰鸣，但人的声音从未消失。」——矿工题词",
        portraitImage = "image/works/film_industrial.png",
        icon         = "🎞️",
    },
    propaganda = {
        title        = "《帝国的荣耀》",
        subtitle     = "宣传题材 · 1907年",
        desc         = "受政府委托拍摄，以壮阔的画面歌颂奥匈帝国的现代化成就——铁路建设、学校兴办、城市规划。影片配乐宏大，每场放映均引来当地权贵观摩。批评者认为其过于粉饰太平，但作为政治宣传工具，效果不可忽视。",
        flavor       = "「一个民族的形象，由谁来书写？」——匿名评论",
        portraitImage = "image/works/film_propaganda.png",
        icon         = "🎞️",
    },
    comedy = {
        title        = "《维也纳来的绅士》",
        subtitle     = "喜剧题材 · 1908年",
        desc         = "一名从维也纳来的官僚误打误撞陷入萨拉热窝的市井生活，与当地居民产生一系列啼笑皆非的误会。影片以幽默的笔触揭示了帝国官僚体制与本地文化之间的隔阂，深受各阶层观众喜爱。",
        flavor       = "「文明的碰撞，往往以笑声开场。」——《萨拉热窝每日报》",
        portraitImage = "image/works/film_comedy.png",
        icon         = "🎞️",
    },
    adventure = {
        title        = "《巴尔干骑士》",
        subtitle     = "冒险题材 · 1909年",
        desc         = "一部充满异域风情的冒险传奇。主人公穿越巴尔干山脉，历经重重险阻，最终找到了一处隐秘的古老遗迹。影片融合了真实的波斯尼亚地理风光与民间传说，吸引了大量外地观众慕名而来。",
        flavor       = "「山的那边是什么？只有走过去的人才知道。」——旅行家格言",
        portraitImage = "image/works/film_adventure.png",
        icon         = "🎞️",
    },
}

-- ============================================================
-- 民族史诗典故
-- ============================================================
WorksLore.EPIC = {
    national = {
        title        = "《波斯尼亚编年史》",
        subtitle     = "民族史诗 · 十四行叙事诗",
        desc         = "以波斯尼亚自古至今的历史为经，以各民族英雄人物为纬，编织而成的鸿篇巨制。全诗共十二章，每章聚焦一个历史时期，从中世纪班王国到奥斯曼统治，再到如今的奥匈时代，气势磅礴，文辞典雅，被誉为「波斯尼亚的荷马史诗」。",
        flavor       = "「记住那些名字，那些在歌谣里永生的名字。」——第一章开篇",
        portraitImage = "image/works/epic_national.png",
        icon         = "📜",
    },
    religious = {
        title        = "《圣约翰之剑》",
        subtitle     = "宗教史诗 · 骑士叙事诗",
        desc         = "以中世纪十字军东征与波斯尼亚贵族的护教故事为主线，描绘了信仰与忠诚的双重考验。诗中穿插大量东正教与伊斯兰教的神话元素，展示了这片土地上多元宗教交融的独特历史。获得了教会与穆斯林社群的共同赞誉，这在当时极为罕见。",
        flavor       = "「剑可以断，誓言不可以。」——骑士誓词",
        portraitImage = "image/works/epic_religious.png",
        icon         = "📜",
    },
    historical = {
        title        = "《斯坦博尔的陷落》",
        subtitle     = "历史史诗 · 悲剧叙事诗",
        desc         = "以1453年君士坦丁堡陷落为背景，通过一名波斯尼亚使节的视角，描写了那场改变世界格局的历史事件。诗中充满宿命与悲壮，将个人命运与帝国兴衰交织在一起，被文学评论界誉为「近十年来最深刻的历史诗作」。",
        flavor       = "「有些陷落是为了给新的崛起让路。」——诗末结语",
        portraitImage = "image/works/epic_historical.png",
        icon         = "📜",
    },
}

-- ============================================================
-- 剧团典故（按培养顺序 t1-t8，身份独立于驻扎地点）
-- ============================================================
WorksLore.TROUPE = {
    t1 = {
        title        = "萨拉热窝国民剧院",
        subtitle     = "常驻剧院 · 始建于1899年",
        desc         = "萨拉热窝最具声望的剧院团体，坐落于巴什察尔希亚集市旁的历史建筑中。剧团汇聚了来自维也纳、布达佩斯和伊斯坦布尔的演员，演出风格融汇欧陆古典与本土传统。每周末的公演场场爆满，是萨拉热窝上流社会的文化聚所。",
        flavor       = "「艺术跨越语言，在这里无论你说塞语还是德语，都能感受到同样的美。」——《波斯尼亚文化报》",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t2 = {
        title        = "涅雷特瓦文化协会",
        subtitle     = "古桥剧团 · 源于莫斯塔尔",
        desc         = "以莫斯塔尔著名的古桥为精神象征，致力于保护和传播黑塞哥维那的民间歌舞与戏剧传统。每年夏天，剧团在古桥下的广场举办露天演出，吸引来自整个黑塞哥维那的观众。南方的阳光与热情赋予了这支剧团独特的生命力。",
        flavor       = "「桥连接两岸，艺术连接人心。」——剧团创始人题词",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t3 = {
        title        = "班亚卢卡皇家剧团",
        subtitle     = "王室认证剧团 · 弗尔巴斯河畔",
        desc         = "曾获奥匈皇室认可的剧团，以严谨的古典戏剧演出著称。长期上演维也纳和布达佩斯的流行剧目，是波斯尼亚北部文化生活的重要支柱。其演员培训体系被誉为「波斯尼亚最系统的戏剧学校」。",
        flavor       = "「皇冠不一定在头上，但艺术的光辉永远不灭。」——剧团院长语",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t4 = {
        title        = "巴尔干巡演剧社",
        subtitle     = "流动剧团 · 行走于波斯尼亚",
        desc         = "一支不知疲倦的巡回演出队伍，穿行于波斯尼亚的大小村镇，将戏剧和音乐带到最偏僻的角落。剧团演员身兼数职，既是演员又是导演和舞台工程师，用最简单的道具创造出令人叹服的舞台效果。他们的到来总是村里最热闹的日子。",
        flavor       = "「艺术不应只属于城市里的人。」——剧团团长",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t5 = {
        title        = "亚得里亚文化剧团",
        subtitle     = "海港剧团 · 融汇地中海风情",
        desc         = "由一群游历过亚得里亚海沿岸城市的艺术家创立，融合了意大利歌剧、克罗地亚民歌与波斯尼亚传统戏剧。剧目风格华丽，擅长以壮阔的舞台布景营造史诗氛围，深受贵族阶层追捧。每逢重大节日，必受邀参与官方庆典演出。",
        flavor       = "「海浪带来了世界，舞台将世界送还给每一个观众。」——创团宣言",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t6 = {
        title        = "德里纳河民俗剧团",
        subtitle     = "民间剧社 · 东波斯尼亚之声",
        desc         = "诞生于德里纳河谷的民间艺术团体，专注于收集和演绎波斯尼亚东部各族群的民俗故事与歌谣。团员多为当地农民和工匠出身，演出朴实而充满感染力。学术界称其为「活的民俗博物馆」，多所欧洲大学曾专程前来研究记录。",
        flavor       = "「泥土里长出来的歌，比任何乐谱都真实。」——民俗学者评语",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t7 = {
        title        = "波赫古典艺术院",
        subtitle     = "学院派剧团 · 精英养成",
        desc         = "由萨拉热窝大学戏剧系教授联合创立，以严格的学院派训练著称。剧团专注于古希腊悲剧和莎士比亚经典的本土化诠释，演员均经过五年以上系统训练。虽然票价不菲，但场场一票难求，是知识分子和精英阶层趋之若鹜的文化殿堂。",
        flavor       = "「伟大的戏剧不会过时，只会换一种语言重新讲述。」——首席导演语",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
    t8 = {
        title        = "萨瓦河青年剧社",
        subtitle     = "革新剧团 · 新生代的舞台",
        desc         = "由一批受过新式教育的年轻艺术家创立，致力于将欧洲最新的戏剧理念引入波斯尼亚。敢于触碰社会禁忌话题，用戏剧探讨工人权利、民族平等和女性解放。当局对其保持警惕，但年轻观众对每一场演出都报以热烈掌声。",
        flavor       = "「今日的叛逆，是明日的经典。」——剧社创始人",
        portraitImage = "image/works/troupe.png",
        icon         = "🎭",
    },
}

-- ============================================================
-- 获取指定作品典故
-- workType: "film" | "national_epic" | "theater_troupe"
-- key: theme（电影/史诗）或 location（剧团）
-- ============================================================
function WorksLore.Get(workType, key)
    if workType == "film" then
        return WorksLore.FILM[key or "historical"] or WorksLore.FILM.historical
    elseif workType == "national_epic" then
        return WorksLore.EPIC[key or "national"] or WorksLore.EPIC.national
    elseif workType == "theater_troupe" then
        local tid = key or "t1"
        return WorksLore.TROUPE[tid] or WorksLore.TROUPE.t1
    end
    return nil
end

return WorksLore
