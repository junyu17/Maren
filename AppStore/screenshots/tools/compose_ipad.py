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
        shot=Image.open(src).convert('RGB').resize((CARD_W,int(CARD_W*H/W)),Image.LANCZOS)
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
