#pragma once

#include <CL/cl.hpp>
#include <acl/acl.hpp>

namespace acl {
  cl::CommandQueue _queue_buffers;

  cl::CommandQueue queue_buffers() {
    if(!_queue_buffers()) {
      _queue_buffers = acl::queue(false);
    }

    return _queue_buffers;
  }

  template<typename T>
  class SharedBuffer {
    const size_t _size;
    T *ptr;
    cl::Buffer buf;

  public:
    SharedBuffer(size_t size) : _size(size) {
      buf = cl::Buffer(acl::context(), CL_MEM_ALLOC_HOST_PTR, size*sizeof(T));
      ptr = (T *) queue_buffers().enqueueMapBuffer(
        buf, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE, 0, size*sizeof(T));
    }

    SharedBuffer() : SharedBuffer(1) {};

    ~SharedBuffer() {
      queue_buffers().enqueueUnmapMemObject(buf, ptr);
    }

    size_t size() const {
      return _size;
    }

    T *data() {
      return ptr;
    }

    cl::Buffer &operator()() {
      return buf;
    }

    T &operator[](size_t i) {
      if(i > _size) {
        throw std::out_of_range(std::to_string(i) + " out of [0," + std::to_string(_size) + ")");
      }
      return ptr[i];
    }
  };
}
