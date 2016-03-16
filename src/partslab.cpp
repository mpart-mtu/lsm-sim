#include <cassert>
#include <tuple>

#include "shadowlru.h"
#include "partslab.h"
#include "mc.h"

partslab::partslab(
    const std::string& filename_suffix,
    size_t partitions)
  : policy{filename_suffix, 0}
  , partitions{partitions}
  , slabs{}
  , size_curve{}
{
  slabs.resize(partitions);
  std::cerr << "Initialized with " << partitions << " partitions" << std::endl;
}

partslab::~partslab() {
} 

size_t partslab::proc(const request *r, bool warmup) {
  assert(r->size() > 0);

  size_t klass = std::hash<decltype(r->kid)>{}(r->kid) % partitions;
  shadowlru& slab_class = slabs.at(klass);

  size_t size_distance = slab_class.proc(r, warmup);
  if (size_distance == PROC_MISS) {
    // Don't count compulsory misses.
    //if (!warmup)
      //size_curve.miss();
    return PROC_MISS;
  }

  const size_t approx_global_size_distance = size_distance * partitions + klass;
  if (!warmup)
    size_curve.hit(approx_global_size_distance);

  return 0;
}

size_t partslab::get_bytes_cached() {
  return 0;
}

void partslab::log() {
  size_curve.dump_cdf("partslab-size-curve" + filename_suffix + ".data");
  dump_util("partslab-util" + filename_suffix + ".data");
}

void partslab::dump_util(const std::string& filename) {}
