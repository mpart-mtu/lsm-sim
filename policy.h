#ifndef POLICY_H
#define POLICY_H

#include <boost/intrusive/list.hpp>

namespace bi = boost::intrusive;

struct req_pair : public bi::list_base_hook<> {
  uint32_t id;
  uint32_t size;
  req_pair (uint16_t i, uint32_t s) : id (i), size(s) {} 
};

inline bool operator == (const req_pair &lhs, const req_pair &rhs) {
  return lhs.id == rhs.id;
}

enum req_typ {
  GET = 1, SET = 2, DEL = 3, ADD = 4, INC = 5, STAT = 6, OTHR = 7 };

struct request {
  double    time;
  int32_t   key_sz;
  int32_t   val_sz;
  uint32_t  kid;
  uint32_t  appid;
  req_typ   type;
  uint8_t   hit;
};

typedef bi::list<req_pair, bi::constant_time_size<false>> queue;

struct delete_disposer {
  void operator()(req_pair *delete_this)
  { delete delete_this; }
};



// abstract base class for plug-and-play policies
class Policy {


  typedef struct dump {
  
    // let k = size of key in bytes
    // let v = size of value in bytes
    // let m = size of metadata in bytes
    // let g = global (total) memory

    double util_oh;     // k+v / g
    double util;        // k+v+m / g
    double ov_head;     // m / g
    double hit_rate;    // sum of hits in hits vect over size of hits vector

  } dump;


  protected: 
    uint64_t global_queue_size;
    uint64_t global_mem;
    queue eviction_queue; 

  public:
    Policy (const uint64_t g) : global_mem(g) {};
    virtual ~Policy () { std::cout << "DESTROY POLICY" << std::endl; }
    virtual bool proc (const request *r) = 0;
    virtual uint32_t get_size() = 0; 

    void log ();
    // virtual get_dump () 
};


#endif