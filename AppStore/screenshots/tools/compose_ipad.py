from PIL import Image, ImageDraw, ImageFont
import os, json

W,H = 2064,2752
TOP=(142,45,65); BOT=(191,70,88)
CARD_W=1569; CARD_X=(W-CARD_W)//2; CARD_Y=540; RADIUS=88
L1_Y=132; L2_Y=312; FS=150
LATIN=('/System/Library/Fonts/Helvetica.ttc',1)
CJK=('/System/Library/Fonts/Hiragino Sans GB.ttc',2)

SHOTS=[('01_calendar',0),('02_perimenopause',1),('03_today',2),('04_trends',3),
       ('05_trackers',4),('07_library',6),('08_search',7),('09_settings','privacy')]
PRIVACY={'en-US':("Your data never","leaves your iPad"),
         'es-ES':("Tus datos no","salen del iPad"),
         'es-MX':("Tus datos no","salen del iPad"),
         'zh-Hans':("数据不离开","你的 iPad")}
caps=json.load(open('captions.json'))

def trim_bottom(im):
    """裁掉屏幕底部最后一段内容,让卡片的圆角落在空白行上。
    否则底部那行文字会被圆角切成半截,看起来像渲染缺陷。"""
    import statistics
    W,H=im.size
    px=im.convert('L').load()
    limit=int(H*0.10)
    step=max(1,W//160)
    def uniform(y):
        vals=[px[x,y] for x in range(0,W,step)]
        return max(vals)-min(vals) <= 6
    for y in range(H-1, H-limit, -1):
        if all(uniform(yy) for yy in range(y-5, y+1)):
            return im.crop((0,0,W,y+1))
    return im

def gradient():
    g=Image.new('RGB',(1,H))
    for y in range(H):
        t=y/(H-1)
        g.putpixel((0,y),tuple(int(TOP[i]+(BOT[i]-TOP[i])*t) for i in range(3)))
    return g.resize((W,H))

def font_for(loc,size):
    p,i = CJK if loc=='zh-Hans' else LATIN
    return ImageFont.truetype(p,size,index=i)

def fit(draw,text,f,loc,maxw):
    size=f.size
    while size>60:
        ff=font_for(loc,size)
        if draw.textlength(text,font=ff)<=maxw: return ff
        size-=6
    return font_for(loc,60)

def compose(loc):
    out=f'final_ipad/{loc}'; os.makedirs(out,exist_ok=True)
    made=[]
    for n,(stem,capidx) in enumerate(SHOTS,1):
        src=f'raw_ipad/{loc}/{stem}.png'
        raw=trim_bottom(Image.open(src).convert('RGB'))
        shot=raw.resize((CARD_W,int(CARD_W*raw.height/raw.width)),Image.LANCZOS)
        canvas=gradient()
        mask=Image.new('L',shot.size,0)
        ImageDraw.Draw(mask).rounded_rectangle([0,0,shot.width-1,shot.height-1],RADIUS,fill=255)
        canvas.paste(shot,(CARD_X,CARD_Y),mask)
        d=ImageDraw.Draw(canvas)
        lines = PRIVACY[loc] if capidx=='privacy' else caps[loc][capidx]
        for text,y in zip(lines,(L1_Y,L2_Y)):
            f=fit(d,text,font_for(loc,FS),loc,W-200)
            w=d.textlength(text,font=f)
            d.text(((W-w)/2,y),text,font=f,fill=(255,255,255))
        p=f'{out}/{n:02d}_{stem.split("_",1)[1]}.png'
        canvas.save(p); made.append(p)
    return made

for loc in ['en-US','es-ES','es-MX','zh-Hans']:
    m=compose(loc); print(loc, len(m))
