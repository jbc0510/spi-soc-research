#!/usr/bin/env python3
import argparse, os, csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

C_NAVY="#002D72"; C_GOLD="#F2A900"; C_RED="#C8102E"; C_TEAL="#00A499"
C_LGRAY="#E8ECF0"; C_DGRAY="#4A5568"

STYLES={
    "mio":       dict(color=C_TEAL, lw=2,   ls="--", marker="s", ms=7,  label="PS MIO (Linux)"),
    "emio":      dict(color=C_NAVY, lw=2.5, ls="-",  marker="o", ms=8,  label="PS EMIO (Linux)"),
    "axi":       dict(color=C_GOLD, lw=2,   ls="-.", marker="^", ms=8,  label="AXI PL (Linux)"),
    "baremetal": dict(color=C_RED,  lw=3,   ls="-",  marker="D", ms=9,  label="PS EMIO (Bare-metal)"),
}

def load(path):
    if not os.path.exists(path): return []
    with open(path) as f:
        return [{k:float(v) for k,v in r.items()} for r in csv.DictReader(f)]

def blabel(b): return f"{int(b)//1024}KB" if b>=1024 else f"{int(b)}B"

def base(w=16,h=9):
    fig,ax=plt.subplots(figsize=(w,h),dpi=120)
    fig.patch.set_facecolor("white"); ax.set_facecolor("white")
    return fig,ax

def style(ax,title,xl,yl):
    ax.set_title(title,fontsize=22,fontweight="bold",color=C_NAVY,pad=18)
    ax.set_xlabel(xl,fontsize=15,color=C_DGRAY,labelpad=10)
    ax.set_ylabel(yl,fontsize=15,color=C_DGRAY,labelpad=10)
    ax.tick_params(labelsize=13,colors=C_DGRAY)
    for sp in ax.spines.values(): sp.set_edgecolor("#CBD5E0")
    ax.grid(True,which="both",color=C_LGRAY,linewidth=1,zorder=0)
    ax.legend(fontsize=13,framealpha=0.95,edgecolor="#CBD5E0",loc="upper left")

def wm(fig):
    fig.text(0.99,0.01,"MSU-2 · ZCU102 SPI Benchmark · CAP Center, Morgan State University",
             ha="right",va="bottom",fontsize=9,color="#A0AEC0",style="italic")

def save(fig,out,name):
    p=os.path.join(out,name); fig.savefig(p,bbox_inches="tight"); plt.close(fig)
    print(f"  ✓ {p}")

def plot_latency(data,out):
    fig,ax=base()
    for k,rows in data.items():
        if not rows: continue
        s=STYLES[k]
        ax.plot([r["bytes"] for r in rows],[r["avg_us"] for r in rows],
                color=s["color"],lw=s["lw"],ls=s["ls"],marker=s["marker"],ms=s["ms"],label=s["label"],zorder=3)
    ax.set_xscale("log",base=2); ax.set_yscale("log")
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(lambda x,_: blabel(x)))
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda y,_: f"{y:,.0f} µs"))
    bm1=next((r["avg_us"] for r in data.get("baremetal",[]) if r["bytes"]==1),None)
    em1=next((r["avg_us"] for r in data.get("emio",[]) if r["bytes"]==1),None)
    if bm1 and em1:
        ax.annotate(f"{em1/bm1:.1f}× faster\nat 1 B",xy=(1,bm1),xytext=(2,bm1*0.35),
                    fontsize=12,color=C_RED,fontweight="bold",
                    arrowprops=dict(arrowstyle="->",color=C_RED,lw=1.5))
    style(ax,"SPI Transfer Latency — All Interfaces (log scale)","Payload Size","Average Latency (µs)")
    wm(fig); save(fig,out,"latency_comparison.png")

def plot_overhead(data,out):
    bm={int(r["bytes"]):r["avg_us"] for r in data.get("baremetal",[])}
    em={int(r["bytes"]):r["avg_us"] for r in data.get("emio",[])}
    xs=sorted(set(bm)&set(em))
    if not xs: return
    ratios=[em[b]/bm[b] for b in xs]
    fig,ax=base()
    bars=ax.bar(range(len(xs)),ratios,color=C_NAVY,alpha=0.85,edgecolor="white",linewidth=1.2,zorder=3)
    for bar,r in zip(bars,ratios):
        if r>=2.0: bar.set_color(C_RED)
        ax.text(bar.get_x()+bar.get_width()/2,bar.get_height()+0.04,
                f"{r:.2f}×",ha="center",va="bottom",fontsize=11,color=C_DGRAY,fontweight="bold")
    ax.set_xticks(range(len(xs))); ax.set_xticklabels([blabel(b) for b in xs],fontsize=12)
    ax.axhline(1.0,color="#A0AEC0",lw=1.5,ls="--",zorder=2)
    ax.set_ylim(0,max(ratios)*1.2)
    ax.set_title("OS Overhead: Linux EMIO vs Bare-Metal Speedup",fontsize=22,fontweight="bold",color=C_NAVY,pad=18)
    ax.set_xlabel("Payload Size",fontsize=15,color=C_DGRAY)
    ax.set_ylabel("Speedup (Linux ÷ Bare-metal latency)",fontsize=15,color=C_DGRAY)
    ax.tick_params(labelsize=13,colors=C_DGRAY)
    ax.grid(True,axis="y",color=C_LGRAY,linewidth=1,zorder=0)
    wm(fig); save(fig,out,"os_overhead.png")

def plot_jitter(data,out):
    fig,ax=base()
    for k,label,color,marker,ls in [
        ("emio","PS EMIO (Linux)",C_NAVY,"o","--"),
        ("baremetal","PS EMIO (Bare-metal)",C_RED,"D","-")]:
        rows=data.get(k,[])
        if not rows: continue
        ax.plot([r["bytes"] for r in rows],[r["stddev_us"] for r in rows],
                color=color,lw=2.5,ls=ls,marker=marker,ms=9,label=label,zorder=3)
    ax.set_xscale("log",base=2); ax.set_yscale("log")
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(lambda x,_: blabel(x)))
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda y,_: f"{y:.3f} µs"))
    style(ax,"Timing Jitter (Stddev) — Linux vs Bare-Metal",
          "Payload Size","Standard Deviation (µs)  — lower is better")
    wm(fig); save(fig,out,"jitter_comparison.png")

def plot_throughput(data,out):
    fig,ax=base()
    for k,rows in data.items():
        if not rows: continue
        s=STYLES[k]
        ys=[(r["bytes"]*8)/r["avg_us"] for r in rows]
        ax.plot([r["bytes"] for r in rows],ys,
                color=s["color"],lw=s["lw"],ls=s["ls"],marker=s["marker"],ms=s["ms"],label=s["label"],zorder=3)
    ax.set_xscale("log",base=2)
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(lambda x,_: blabel(x)))
    style(ax,"SPI Throughput — All Interfaces","Payload Size","Throughput (Mbps)")
    wm(fig); save(fig,out,"throughput_comparison.png")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--dir",default=".")
    ap.add_argument("--out",default=".")
    args=ap.parse_args()
    os.makedirs(args.out,exist_ok=True)
    data={k:load(os.path.join(args.dir,f"{k}_results.csv"))
          for k in ["mio","emio","axi","baremetal"]}
    for k,rows in data.items(): print(f"  {k:12s}: {len(rows)} rows" if rows else f"  {k:12s}: NOT FOUND")
    plot_latency(data,args.out)
    plot_overhead(data,args.out)
    plot_jitter(data,args.out)
    plot_throughput(data,args.out)
    print("Done.")

if __name__=="__main__": main()
