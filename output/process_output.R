
library(reshape2)
library(ggplot2)
#library(svglite)
library(stringi)
library(plyr)
options(scipen=-1)


plots <- c("aet.out","cliffhanger.out")
#plots <- c("etc.out")

atlist = list()
ctlist = list()

# 3 is etc_15
# 4 is ycsb

for (i in plots ) 
{

    df <- read.table(i,header=TRUE)
    
    prefix <- toupper(unlist(strsplit(i,"\\."))[1] )
    prefix <- paste(prefix,": ",sep="")

    print(prefix)

    #instant hit rate
    etc.ihr <- subset(df,app == 1 & subpolicy == "normal" & w_hit_rate != -1, select=c(accesses,w_hit_rate) )
    psa.ihr <- subset(df,app == 2 & subpolicy == "normal" & w_hit_rate != -1, select=c(accesses,w_hit_rate) )
    n <- min(nrow(etc.ihr),nrow(psa.ihr))
    avg.ihr <- data.frame(accesses=etc.ihr[1:n,"accesses"],
                          w_hit_rate=(etc.ihr[1:n,"w_hit_rate"]+psa.ihr[1:n,"w_hit_rate"])/2)


    ihrlist <- list()
    ihrlist[["avg"]] = avg.ihr
    ihrlist[["psa"]] = psa.ihr
    ihrlist[["etc"]] = etc.ihr
    

    #avg hit rate
    etc.ahr <- subset(df,app == 1 & subpolicy == "normal" , select=c(accesses,hit_rate) )
    psa.ahr <- subset(df,app == 2 & subpolicy == "normal" , select=c(accesses,hit_rate) )
    n <- min(nrow(etc.ahr),nrow(psa.ahr))
    avg.ahr <- data.frame(accesses=etc.ahr[1:n,"accesses"],
                          hit_rate=(etc.ahr[1:n,"hit_rate"]+psa.ahr[1:n,"hit_rate"])/2)
    
    ahrlist <- list()
    ahrlist[["avg"]] = avg.ahr
    ahrlist[["psa"]] = psa.ahr
    ahrlist[["etc"]] = etc.ahr
    
    
    etcitems <- subset(df,app == 1 & subpolicy == "normal", select=c(accesses,live_items) )
    psaitems <- subset(df,app == 2 & subpolicy == "normal" , select=c(accesses,live_items) )
    
    itemslist <- list()
    itemslist[["etc"]] = etcitems
    itemslist[["psa"]] = psaitems
    
    etcshq <- subset(df,app == 1  & subpolicy == "normal", select=c(accesses,shadow_q_hits) )
    psashq <- subset(df,app == 2  & subpolicy == "normal", select=c(accesses,shadow_q_hits) )
    
    shqlist <- list()
    shqlist[["etc"]] = etcshq
    shqlist[["psa"]] = psashq
    
    shslist <- list()
    
    htslist <- list()
    
    #if we are on cliffhanger, take the shadowq size
    if (i == "cliffhanger.out")
    {
        etcshs <- subset(df,app == 1  & subpolicy == "normal", select=c(accesses,shq_size) )
        psashs <- subset(df,app == 2  & subpolicy == "normal", select=c(accesses,shq_size) )
    
        shslist[["etc"]] = etcshs
        shslist[["psa"]] = psashs
    }
    # else get the AET_hash table size
    else
    {
        etchts <- subset(df,app == 1  & subpolicy == "normal", select=c(accesses,AET_ht_size) )
        psahts <- subset(df,app == 2  & subpolicy == "normal", select=c(accesses,AET_ht_size) )
    
        htslist[["etc"]] = etchts
        htslist[["psa"]] = psahts

    }
    

    #important to note that is is allocated memory
    etctmem <- subset(df,app == 1  & subpolicy == "normal", select=c(accesses,share) )
    psatmem <- subset(df,app == 2  & subpolicy == "normal", select=c(accesses,share) )
    
    #divide by 200 to express as number of objects
    etctmem$total = etctmem$share/200 
    psatmem$total = psatmem$share/200
    
    etctmem <- subset(etctmem, select=c(accesses,total) )
    psatmem <- subset(psatmem, select=c(accesses,total) )
    
    tmemlist <- list()
    tmemlist[["etc"]] = etctmem
    tmemlist[["psa"]] = psatmem
   

    ##BEGIN PLOTTING

    #1. HIT RATE (AVG AND INST) VS ALLOC MEM
    #2. HIT RATE (AVG AND INST) VS LIVE ITEMS
    #3. SHADOW QUEUE

    hrc_df = melt(ihrlist, id="accesses")
    tmem_df = melt(tmemlist, id="accesses")
    item_df = melt(itemslist, id="accesses")
    shq_df = melt(shqlist, id="accesses")

    shqs_df = melt(shslist, id="accesses")
    hts_df = melt(htslist, id="accesses")
   
    lblpsa = "psa"
    lbletc = "etc"
    lblavg = "avg"
    
    #should take a list of dfs
    get_last_values <- function(dflist)
    {
        lbl.list <- list()
        last.df <- data.frame(matrix(ncol = 3, nrow = 0))
        colnames(last.df) <- c("accesses","value","lbl")
        i = 1
        for (n in names(dflist))
        {
            lastaccess = dflist[[n]][nrow(dflist[[n]]),1]
            lastvalue = dflist[[n]][nrow(dflist[[n]]),2]
            if (lastvalue < 1) 
            {
                last.df[i,] = list(accesses=lastaccess,value=lastvalue,lbl = paste(as.character(round(lastvalue,3)),n)) 
                lbl.list[[n]] = paste(as.character(round(lastvalue,3)),n)
            }
            else
            {
                options(scipen=999)
                last.df[i,] = list(accesses=lastaccess,value=lastvalue,lbl = paste(as.character(round(lastvalue,-3)),n)) 
                lbl.list[[n]] = paste(as.character(round(lastvalue,-3)),n)
                options(scipen=-1)
            }
            i = i + 1
        }
        return (list(data=last.df,lbl=lbl.list))
    }

    hr_vs_allocated <- function(ahrc_df,atmem_df,prefix,dflist, odflist, hrt)
    {
       
       title <- paste(prefix, hrt, " Hit Rate and Allocated Objects vs. Accesses",sep="")
       
       last = get_last_values(dflist)
       last.df = last[["data"]]
       labels = last[["lbl"]]
       
       lasto = get_last_values(odflist)
       lasto.df = lasto[["data"]]
       labelso = lasto[["lbl"]]
        
       
       p <- ggplot() +
            geom_line(data=ahrc_df, aes(x=accesses, y=value, colour=L1) ) +
            geom_line(data=atmem_df, aes(x=accesses, y=value/10000000, colour=L1), linetype = "dashed") +
            theme_bw() +
            theme(legend.position="bottom", legend.box = "horizontal", aspect.ratio=1) +
            expand_limits(y=c(0,1)) +
            scale_y_continuous(sec.axis = sec_axis(~.*10000000, name = "Allocated Objects", 
                                                   breaks = round(seq(0,
                                                                      10000000, 
                                                                      by = 1000000),1)), 
                               breaks = round(seq(0,1, by = 0.1),1)) +
            scale_x_continuous(breaks = round(seq(0,50000000, by = 10000000),1)) +
            geom_text(data=last.df,aes(x=accesses, y=value, label=lbl),hjust=1,vjust=0) +
            geom_text(data=lasto.df,aes(x=accesses, y=value/10000000, label=lbl),hjust=1,vjust=0) +
            scale_colour_manual(values = c("etc" = "#F8766D", "psa" = "#619CFF", "avg" = "#00BA38") ) +
            labs(title = title, 
                 y = "Hit Rate", 
                 x = "Accesses (logical access)",
                 colour = "" ) 
        return(p)
    }
    
    hr_vs_items <- function(ahrc_df,aitem_df,prefix,dflist,odflist,hrt)
    {
       title <- paste(prefix, hrt, " Hit Rate and Live Objects vs. Accesses",sep="")

       last = get_last_values(dflist)
       last.df = last[["data"]]
       labels = last[["lbl"]]
       
       lasto = get_last_values(odflist)
       lasto.df = lasto[["data"]]
       labelso = lasto[["lbl"]]
       
      
       p <- ggplot() +
            geom_line(data=ahrc_df, aes(x=accesses, y=value, colour=L1) ) +
            geom_line(data=aitem_df, aes(x=accesses, y=value/10000000, colour=L1), linetype = "dashed") +
            theme_bw() +
            theme(legend.position="bottom", legend.box = "horizontal", aspect.ratio=1) +
            expand_limits(y=c(0,1)) +
            scale_y_continuous(sec.axis = sec_axis(~.*10000000, name = "Live Objects",
                                                   breaks = round(seq(0,
                                                                      10000000, 
                                                                      by = 1000000),1)), 
                               breaks = round(seq(0,1, by = 0.1),1)) +
            scale_x_continuous(breaks = round(seq(0,50000000, by = 10000000),1)) +
            geom_text(data=last.df,aes(x=accesses, y=value, label=lbl),hjust=1,vjust=0) +
            geom_text(data=lasto.df,aes(x=accesses, y=value/10000000, label=lbl),hjust=1,vjust=0) +
            scale_colour_manual(values = c("etc" = "#F8766D", "psa" = "#619CFF", "avg" = "#00BA38") ) +
            labs(title = title, 
                 y = "Hit Rate", 
                 x = "Accesses (logical access)",
                 colour = "" ) 
        return(p)
    }


    #inst hr
    plot(hr_vs_allocated(hrc_df,tmem_df,prefix,ihrlist,tmemlist,"Current"))
    plot(hr_vs_items(hrc_df,item_df,prefix,ihrlist,itemslist,"Current"))

    #running avg hr
    hrc_df = melt(ahrlist, id="accesses")
    plot(hr_vs_allocated(hrc_df,tmem_df,prefix,ahrlist,tmemlist,"Average"))
    plot(hr_vs_items(hrc_df,item_df,prefix,ahrlist,itemslist,"Average"))

    #shadow queue 
    title <- paste(prefix,"Shadow Queue Hits vs. Accesses",sep="")
    plot(ggplot(data=shq_df, aes(x=accesses, y=value, colour=L1) ) +
        geom_line() +
        theme_bw() +
        theme(legend.position="bottom", legend.box = "horizontal", aspect.ratio=1) +
        expand_limits(y=0) +
        labs(title = title, 
             y = "Shadow Queue Hits", 
             x = "Accesses (logical accesses)",
             colour = "" ) )
    
    if (i == "cliffhanger.out")
    {
        #shadow queue sizes
        title <- paste(prefix,"Shadow Queue Size vs. Accesses",sep="")
        plot(ggplot(data=shqs_df, aes(x=accesses, y=value, colour=L1) ) +
            geom_line() +
            theme_bw() +
            theme(legend.position="bottom", legend.box = "horizontal", aspect.ratio=1) +
            expand_limits(y=0) +
            labs(title = title, 
                 y = "Size (keys)", 
                 x = "Accesses (logical accesses)",
                 colour = "" ) )
    }
    else
    {
        #shadow queue sizes
        title <- paste(prefix,"Hash Table Size vs. Accesses",sep="")
        plot(ggplot(data=hts_df, aes(x=accesses, y=value, colour=L1) ) +
            geom_line() +
            theme_bw() +
            theme(legend.position="bottom", legend.box = "horizontal", aspect.ratio=1) +
            expand_limits(y=0) +
            labs(title = title, 
                 y = "Size (objects)", 
                 x = "Accesses (logical accesses)",
                 colour = "" ) )
    }
    
    
}



