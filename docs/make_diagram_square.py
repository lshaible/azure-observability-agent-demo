import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

AZ_BLUE="#0078D4"; AZ_DARK="#243A5E"; GREY="#5B5B66"; LIGHT="#F3F7FC"
RED="#C0392B"; GREEN="#107C41"; PURPLE="#5C2D91"; CARD_EDGE="#D4E3F2"

fig, ax = plt.subplots(figsize=(10.8,10.8), dpi=100)
ax.set_xlim(0,100); ax.set_ylim(0,100); ax.axis("off")
fig.patch.set_facecolor("white")

ax.text(50,95,"Modern Observability",ha="center",va="center",
        fontsize=30,fontweight="bold",color=AZ_DARK)
ax.text(50,90.3,"from telemetry  \u2192  root cause, automatically",
        ha="center",va="center",fontsize=15,color=GREY)

def card(x,y,w,h,title,sub,edge=CARD_EDGE,fill=LIGHT,tcolor=AZ_DARK,
         scolor=GREY,tfs=15,sfs=10.5):
    ax.add_patch(FancyBboxPatch((x,y),w,h,
        boxstyle="round,pad=0.3,rounding_size=1.4",
        linewidth=2,edgecolor=edge,facecolor=fill))
    ax.text(x+w/2,y+h*0.62,title,ha="center",va="center",
            fontsize=tfs,fontweight="bold",color=tcolor)
    if sub:
        ax.text(x+w/2,y+h*0.26,sub,ha="center",va="center",fontsize=sfs,color=scolor)

def darrow(x,y1,y2,color=AZ_BLUE,lw=3):
    ax.add_patch(FancyArrowPatch((x,y1),(x,y2),arrowstyle="-|>",
        mutation_scale=22,linewidth=lw,color=color))

# centered vertical pipeline
cx=14; cw=48; cmid=cx+cw/2
ys=[78,64,50,33,17]; h=10
card(cx,ys[0],cw,h,"Web App","Flask on App Service   /error -> 500",edge="#E6C9C4")
card(cx,ys[1],cw,h,"Telemetry","Application Insights + Log Analytics (KQL)")
card(cx,ys[2],cw,h,"Alerts","Metric alert  +  Log-query alert",edge="#F2E2C4")
card(cx,ys[3],cw,h+3,"Observability Agent","autonomous AI  \u2022  correlate \u2022 investigate",
     edge="#D9CBEA",fill="#F4EEFB",tcolor=PURPLE,tfs=16)
card(cx,ys[4],cw,h+1,"Root-caused Issue","names the failing endpoint + the exception",
     edge="#BFE3CC",fill="#EAF6EF",tcolor=GREEN,tfs=16)

darrow(cmid,ys[0],ys[1]+h); ax.text(cmid+1.5,(ys[0]+ys[1]+h)/2,"OpenTelemetry",ha="left",fontsize=8.5,color=GREY)
darrow(cmid,ys[1],ys[2]+h); ax.text(cmid+1.5,(ys[1]+ys[2]+h)/2,"thresholds",ha="left",fontsize=8.5,color=GREY)
darrow(cmid,ys[2],ys[3]+h+3,color=PURPLE); ax.text(cmid+1.5,(ys[2]+ys[3]+h+3)/2,"watches",ha="left",fontsize=8.5,color=PURPLE)
darrow(cmid,ys[3],ys[4]+h+1,color=PURPLE); ax.text(cmid+1.5,(ys[3]+ys[4]+h+1)/2,"creates",ha="left",fontsize=9,color=PURPLE,fontweight="bold")

# human in the loop (right of alerts)
hx=70; hw=26
card(hx,ys[2]-1,hw,h+2,"Human-\nin-the-loop","manually\nInvestigate\nany alert",
     edge="#CBD6E2",fill="#EEF3F8",tfs=12,sfs=9.5)
ax.add_patch(FancyArrowPatch((cx+cw,ys[2]+h/2),(hx,ys[2]+h/2),
    arrowstyle="<|-|>",mutation_scale=16,linewidth=2,color=GREY,linestyle=(0,(4,3))))
ax.text((cx+cw+hx)/2,ys[2]+h/2+2.2,"you stay\nin control",ha="center",fontsize=8.5,color=GREY,style="italic")

# before / after
ax.add_patch(FancyBboxPatch((6,5.5),88,7,boxstyle="round,pad=0.3,rounding_size=1.2",
    linewidth=0,facecolor="#0E2440"))
ax.text(10,9,"BEFORE",ha="left",va="center",fontsize=10.5,fontweight="bold",color="#7FB2E5")
ax.text(23,9,"30 min of tab-hopping",ha="left",va="center",fontsize=10.5,color="white")
ax.text(56,9,"AFTER",ha="left",va="center",fontsize=10.5,fontweight="bold",color="#76D7A0")
ax.text(67,9,"start at the answer",ha="left",va="center",fontsize=10.5,color="white")

ax.text(50,2.4,"github.com/lshaible/azure-observability-agent-demo  \u2022  Azure Monitor Observability Agent (preview)",
        ha="center",va="center",fontsize=9,color=GREY)

plt.subplots_adjust(left=0,right=1,top=1,bottom=0)
out=r"C:\Observability\obs-demo\docs\observability-agent-architecture-square.png"
plt.savefig(out,dpi=100,facecolor="white")
print("saved",out)
