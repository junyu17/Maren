from PIL import Image, ImageDraw, ImageFont
import os, json
W,H=1320,2868
TOP=(142,45,65); BOT=(191,70,88)
CARD_W=1003; CARD_X=(W-CARD_W)//2; CARD_Y=580; RADIUS=56
L1_Y=150; L2_Y=330; FS=135
LATIN=('/System/Library/Fonts/Helvetica.ttc',1)
CJK=('/System/Library/Fonts/Hiragino Sans GB.ttc',2)
SHOTS=[('01_calendar',0),('02_perimenopause',1),('03_today',2),('04_trends',3),('05_trackers',4),('07_library',6),('08_search',7),('09_settings','privacy')]
PRIVACY={'en-US':("Your data never","leaves your phone"),'es-ES':("Tus datos no","salen del mo\u0301vil"),'es-MX':("Tus datos no","salen del celular"),'zh-Hans':("\u6570\u636e\u4e0d\u79bb\u5f00","\u4f60\u7684\u624b\u673a")}
caps=json.load(open('captions.json'))
def gradient():
    g=Image.new('RGB',(1,H))
    for y in range(H):
        t=y/(H-1); g.putpixel((0,y),tuple(int(TOP[i]+(BOT[i]-TOP[i])*t) for i in range(3)))
    return g.resize((W,H))
def font_for(loc,size):
    p,i = CJK if loc=='zh-Hans' else LATIN
    return ImageFont.truetype(p,size,index=i)
def fit(d,text,loc,maxw):
    s=FS
    while s>60:
        f=font_for(loc,s)
        if d.textlength(text,font=f)<=maxw: return f
        s-=5
    return font_for(loc,60)
for loc in ['en-US','es-ES','es-MX','zh-Hans']:
    out=f'final_iphone/{loc}'; os.makedirs(out,exist_ok=True)
    for n,(stem,capidx) in enumerate(SHOTS,1):
        shot=Image.open(f'raw_iphone/{loc}/{stem}.png').convert('RGB').resize((CARD_W,int(CARD_W*H/W)),Image.LANCZOS)
        canvas=gradient()
        mask=Image.new('L',shot.size,0)
        ImageDraw.Draw(mask).rounded_rectangle([0,0,shot.width-1,shot.height-1],RADIUS,fill=255)
        canvas.paste(shot,(CARD_X,CARD_Y),mask)
        d=ImageDraw.Draw(canvas)
        lines = PRIVACY[loc] if capidx=='privacy' else caps[loc][capidx]
        for text,y in zip(lines,(L1_Y,L2_Y)):
            f=fit(d,text,loc,W-140); w=d.textlength(text,font=f)
            d.text(((W-w)/2,y),text,font=f,fill=(255,255,255))
        canvas.save(f'{out}/{n:02d}_{stem.split("_",1)[1]}.png')
    print(loc,'done')
