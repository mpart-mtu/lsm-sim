#include <list>
#include <unordered_map>
#include <vector>
#include <deque>
#include <algorithm>
#include <map>
#include <limits>

#include "common.h"
#include "lru.h"
#include "mrc.h"
#include "policy.h"

#ifndef LSC_MULTI_H
#define LSC_MULTI_H

extern size_t AET_repart;
extern size_t CH_shq_size;

extern size_t W_LEN; //window to take inst hit rate
extern bool lru_test; //do lru test, no sharing between apps => reserved == 100%
extern size_t noisyN; //appid of noisy neighbor

class lsc_multi : public policy {
  public:
    enum class cleaning_policy { RANDOM, RUMBLE, ROUND_ROBIN, OLDEST_ITEM, LOW_NEED };
    enum class subpolicy { NORMAL, GREEDY, STATIC };

    static constexpr size_t idle_mem_secs = 5 * 60 * 60;

  private:
    class segment;

    class item {
      public:
        item(segment* seg, const request& req)
          : seg{seg}
          , req{req}
        {}

        // Sorting by request timestamp is ok, because we also
        // store the request object even when the access is a
        // hit to an existing object. That is, timestamps
        // represent access times as a result.
        static bool rcmp(const item* left, const item* right) {
          return left->req.time > right->req.time;
        }

        segment* seg;
        request req;
    };

    typedef std::list<item> lru_queue; 
    typedef std::unordered_map<uint64_t, lru_queue::iterator> hash_map;

    class segment {
      public:
        segment()
          : queue{}
          , app_bytes{}
          , filled_bytes{}
          , access_count{}
          , low_timestamp{}
        {}

        lru_queue queue;
        std::unordered_map<uint64_t, uint64_t> app_bytes;

        uint64_t filled_bytes;

        uint64_t access_count;
        double low_timestamp;
    };

    class application {
      public:
        application(size_t appid,
                    size_t min_mem_pct,
                    size_t target_mem,
                    size_t steal_size,
                    bool u_mrc);
        ~application();

        size_t bytes_limit() const {
          return target_mem + credit_bytes;
        }

        bool try_steal_from(application& other, size_t bytes) {
          if (other.bytes_limit() < bytes)
            return false;

          if (&other == this)
            return false;

          const size_t would_become = other.bytes_limit() - bytes;
          if (would_become < other.min_mem)
            return false;

          other.credit_bytes -= bytes;
          credit_bytes += bytes;

          return true;
        }

        bool would_hit(const request *r) {
          return shadow_q.would_hit(r);
        }

        void add_to_cleaning_queue(item* item) {
          cleaning_q.emplace_back(item);
        }

        void sort_cleaning_queue() {
          std::sort(cleaning_q.begin(),
                    cleaning_q.end(),
                    item::rcmp);
          cleaning_it = cleaning_q.begin();
        }

        static void dump_stats_header() {
          std::cout << "time "
                    << "app "
                    << "subpolicy "
                    << "target_mem "
                    << "credit_bytes "
                    << "share "
                    << "min_mem "
                    << "min_mem_pct "
                    << "steal_size "
                    << "bytes_in_use "
                    << "need "
                    << "hits "
                    << "accesses "
                    << "shadow_q_hits "
                    << "survivor_items "
                    << "survivor_bytes "
                    << "evicted_items "
                    << "evicted_bytes "
                    << "hit_rate " //avg hit rate
                    << "w_hit_rate " //get the window hit rate
                    << "live_items " //number of objects currently in cache
                    << "misses "
                    << "miss_rate "
                    << "shq_size "
                    << "AET_ht_size "
                    << std::endl;
        }

        void dump_stats(double time, subpolicy policy) {
          const char* policy_name[3] = { "normal"
                                       , "greedy"
                                       , "static"
                                       };
          //this is our window that we look at
          //100k is good for average
          double w_rate = -1;
          //std::cout << "a: " << accesses << "\n";
          //std::cout << "w: " << w_accesses << "\n";
          //std::cout << "a-w: " << accesses-w_accesses << "\n";
          //NEED TO CHANGE ACCORDING TO WRKLOAD LEN?
          if ( (w_accesses) >= W_LEN )
          {
                w_rate = double(w_hits) / (w_accesses); 
                w_accesses = 0;
                w_hits = 0;
          }

          std::cout << int64_t(time) << " "
                    << appid << " "
                    << policy_name[uint32_t(policy)] << " "
                    << target_mem << " "
                    << credit_bytes << " "
                    << target_mem + credit_bytes << " "
                    << min_mem << " "
                    << min_mem_pct << " "
                    << steal_size << " "
                    << bytes_in_use << " "
                    << need() << " "
                    << hits << " "
                    << accesses << " "
                    << shadow_q_hits << " "
                    << survivor_items << " "
                    << survivor_bytes << " "
                    << evicted_items << " "
                    << evicted_bytes << " "
                    << double(hits) / accesses << " "
                    << w_rate << " "
                    << live_items << " "
                    << misses << " "
                    << double(misses)/accesses << " "
                    << shadow_q.get_size() << " "
                    << AET.get_hash_table_size() << " "
                    << std::endl;
        }

        double need() {
            return double(target_mem + credit_bytes) / (live_items*OSIZE);
        }

        const size_t appid;
        const size_t min_mem_pct;
        size_t target_mem;
        const size_t min_mem;
        const size_t steal_size;

        ssize_t credit_bytes;

        size_t bytes_in_use;
        size_t live_items;

        size_t accesses;
        size_t lastmrc;
        size_t hits;
        size_t misses;
        size_t w_accesses;
        size_t w_hits;
        size_t shadow_q_hits;
        size_t survivor_items;
        size_t survivor_bytes;
        size_t evicted_items;
        size_t evicted_bytes;
        //USE MRC over shadow queue
        bool u_mrc;
        mrc AET;

        lru shadow_q;

        std::deque<item*> cleaning_q;
        std::deque<item*>::iterator cleaning_it;
        

        
    };

  public:
    lsc_multi(stats sts, subpolicy eviction_policy);
    ~lsc_multi();

    void add_app(size_t appid,
                 size_t min_memory_pct,
                 size_t target_memory,
                 size_t steal_size,
                 bool u_mrc);

    void set_tax(double tax_rate)
    {
      use_tax = true;
      this->tax_rate = tax_rate;
    }

    size_t proc(const request *r, bool warmup);
    size_t proc_net(const request *r, bool warmup);
    size_t get_bytes_cached() const;
   
    double get_running_hit_rate();
    size_t get_evicted_bytes() { return stat.evicted_bytes; }
    size_t get_evicted_items() { return stat.evicted_items; }

    void dump_util(const std::string& filename);

    virtual void dump_stats(void) {}

  private:




    void arbitrate();
    void arbitrate_greedy();
    void arbitrate_greedyFast();
    void arbitrate_ilp();
    void arbitrate_sa();
    void rollover(double timestamp);
    void clean();
    void dump_usage();

    std::vector<segment*> choose_cleaning_sources();
    std::vector<segment*> choose_cleaning_sources_random();
    std::vector<segment*> choose_cleaning_sources_rumble();
    std::vector<segment*> choose_cleaning_sources_round_robin();
    std::vector<segment*> choose_cleaning_sources_oldest_item();
    std::vector<segment*> choose_cleaning_sources_low_need();
    segment* choose_cleaning_destination();
    auto choose_survivor() -> application*;

    void dump_cleaning_plan(std::vector<segment*> srcs,
                            std::vector<segment*> dsts);

    void dump_app_stats(double time);

    void compute_idle_mem(double time);

    double last_idle_check;
    double last_dump;

    bool use_tax;
    double tax_rate;

    subpolicy eviction_policy;
    cleaning_policy cleaner;

    std::unordered_map<size_t, application> apps;

    hash_map map; 

    segment* head;
    std::vector<optional<segment>> segments;
    size_t free_segments;

    lsc_multi(const lsc_multi&) = delete;
    lsc_multi& operator=(const lsc_multi&) = delete;
    lsc_multi(lsc_multi&&) = delete;
    lsc_multi& operator=(lsc_multi&&) = delete;
};

#endif
