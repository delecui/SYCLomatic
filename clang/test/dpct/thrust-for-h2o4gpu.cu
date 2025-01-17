// UNSUPPORTED: cuda-8.0
// UNSUPPORTED: v8.0
// RUN: dpct --format-range=none -out-root %T/thrust-for-h2o4gpu %s --cuda-include-path="%cuda-path/include" -- -std=c++14 -x cuda --cuda-host-only -fno-delayed-template-parsing
// RUN: FileCheck --input-file %T/thrust-for-h2o4gpu/thrust-for-h2o4gpu.dp.cpp --match-full-lines %s


// CHECK: #include <oneapi/dpl/execution>
// CHECK-NEXT: #include <oneapi/dpl/algorithm>
// CHECK-NEXT: #include <CL/sycl.hpp>
// CHECK-NEXT: #include <dpct/dpct.hpp>
// CHECK-NEXT: #include <dpct/dpl_utils.hpp>
#include <thrust/copy.h>
#include <thrust/device_vector.h>
#include <thrust/execution_policy.h>
#include <thrust/random.h>
#include <thrust/reduce.h>
#include <algorithm>
#include <thrust/inner_product.h>
#include <thrust/extrema.h>
#include <thrust/host_vector.h>
#include <thrust/gather.h>
#include <thrust/scatter.h>

template <typename T> struct is_even {
  __host__ __device__ bool operator()(T x) {
    return (static_cast<unsigned int>(x) & 1) == 0;
  }
};

template <typename T> struct absolute_value {
  __host__ __device__ void operator()(T &x) const { x = (x > 0 ? x : -x); }
};

//CHECK: template<typename ExecutionPolicy, typename Iterator1, typename Iterator2, typename Predicate, typename Iterator3>
//CHECK-NEXT: void copy_if_kernel(ExecutionPolicy exec, Iterator1 first, Iterator1 last, Iterator2 result1, Predicate pred, Iterator3 result2)
//CHECK-NEXT: {
//CHECK-NEXT:   *result2 = std::copy_if(first, last, result1, pred);
//CHECK-NEXT: }
template<typename ExecutionPolicy, typename Iterator1, typename Iterator2, typename Predicate, typename Iterator3>
__global__ void copy_if_kernel(ExecutionPolicy exec, Iterator1 first, Iterator1 last, Iterator2 result1, Predicate pred, Iterator3 result2)
{
  *result2 = thrust::copy_if(exec, first, last, result1, pred);
}

template<typename ExecutionPolicy>
void copy_if_device(ExecutionPolicy exec)
{
  size_t n = 1000;

  //CHECK: std::vector<int>   h_data (n, 1);
  //CHECK-NEXT: dpct::device_vector<int> d_data = h_data;
  //CHECK-NEXT: dpct::device_vector<int> d_result(n);
  //CHECK-NEXT: dpct::device_vector<typename dpct::device_vector<int>::iterator> dd(1);
  thrust::host_vector<int>   h_data (n, 1);
  thrust::device_vector<int> d_data = h_data;
  thrust::device_vector<int> d_result(n);
  thrust::device_vector<typename thrust::device_vector<int>::iterator> dd(1);

  //CHECK: dpct::get_default_queue().submit(
  //CHECK-NEXT:  [&](sycl::handler &cgh) {
  //CHECK-NEXT:    auto d_data_begin_ct1 = d_data.begin();
  //CHECK-NEXT:    auto d_data_end_ct2 = d_data.end();
  //CHECK-NEXT:    auto d_result_begin_ct3 = d_result.begin();
  //CHECK-NEXT:    auto dd_begin_ct5 = dd.begin();
  //CHECK-EMPTY:
  //CHECK-NEXT:    cgh.parallel_for(
  //CHECK-NEXT:      sycl::nd_range<3>(sycl::range<3>(1, 1, 1), sycl::range<3>(1, 1, 1)),
  //CHECK-NEXT:      [=](sycl::nd_item<3> item_ct1) {
  //CHECK-NEXT:        copy_if_kernel(exec, d_data_begin_ct1, d_data_end_ct2, d_result_begin_ct3, is_even<int>(), dd_begin_ct5);
  //CHECK-NEXT:      });
  //CHECK-NEXT:  });
  copy_if_kernel<<<1,1>>>(exec, d_data.begin(), d_data.end(), d_result.begin(), is_even<int>(), dd.begin());
}

template<typename T>
struct isfoo_test {
    __host__ __device__ bool operator()(const T a) const { return true; }
};

void foo() {
  //CHECK: copy_if_device(oneapi::dpl::execution::seq);
  copy_if_device(thrust::seq);

  //CHECK: std::vector<int> h_data(10, 1);
  //CHECK-NEXT: std::vector<int> h_result(10);
  //CHECK-NEXT: dpct::device_vector<int> *data[10];
  //CHECK-NEXT: dpct::device_vector<int> d_new_potential_centroids(10);
  //CHECK-NEXT: auto range = dpct::make_counting_iterator(0);
  thrust::host_vector<int> h_data(10, 1);
  thrust::host_vector<int> h_result(10);
  thrust::device_vector<int> *data[10];
  thrust::device_vector<int> d_new_potential_centroids(10);
  auto range = thrust::make_counting_iterator(0);

  //CHECK: std::copy_if(oneapi::dpl::execution::make_device_policy(q_ct1), h_data.begin(), h_data.end(), h_result.begin(), is_even<int>());
  //CHECK-NEXT: std::copy_if(oneapi::dpl::execution::seq, h_data.begin(), h_data.end(), h_result.begin(), is_even<int>());
  //CHECK-NEXT: dpct::copy_if(oneapi::dpl::execution::make_device_policy(q_ct1), (*data[0]).begin(), (*data[0]).end(), range, d_new_potential_centroids.begin(),[=] (int idx) { return true; });
  thrust::copy_if(h_data.begin(), h_data.end(), h_result.begin(), is_even<int>());
  thrust::copy_if(thrust::seq, h_data.begin(), h_data.end(), h_result.begin(), is_even<int>());
  thrust::copy_if((*data[0]).begin(), (*data[0]).end(), range, d_new_potential_centroids.begin(),[=] __device__(int idx) { return true; });

  //CHECK: std::vector<dpct::device_vector<int>> d(10);
  //CHECK-NEXT: auto t = dpct::make_counting_iterator(0);
  //CHECK-NEXT: auto min_costs_ptr = dpct::get_raw_pointer(d[0].data());
  //CHECK-NEXT: int pot_cent_num = std::count_if(oneapi::dpl::execution::make_device_policy(q_ct1), t, t + 10, [=] (int idx) { return true;});
  std::vector<thrust::device_vector<int>> d(10);
  auto t = thrust::make_counting_iterator(0);
  auto min_costs_ptr = thrust::raw_pointer_cast(d[0].data());
  int pot_cent_num = thrust::count_if(t, t + 10, [=] __device__(int idx) { return true;});

  {
  float *_de = NULL;
  float fill_value = 0.0;

  //CHECK: dpct::device_pointer<float> dev_ptr = dpct::get_device_pointer(static_cast<float *>(&_de[0]));
  //CHECK-NEXT: std::fill(oneapi::dpl::execution::make_device_policy(q_ct1), dev_ptr, dev_ptr + 10, fill_value);
  //CHECK-NEXT: std::fill_n(oneapi::dpl::execution::make_device_policy(q_ct1), dev_ptr, 10, fill_value);
  //CHECK-NEXT: float M_inner = dpct::inner_product(oneapi::dpl::execution::make_device_policy(q_ct1), dev_ptr, dev_ptr + 10, dev_ptr, 0.0f);
  thrust::device_ptr<float> dev_ptr = thrust::device_pointer_cast(static_cast<float *>(&_de[0]));
  thrust::fill(dev_ptr, dev_ptr + 10, fill_value);
  thrust::fill_n(dev_ptr, 10, fill_value);
  float M_inner = thrust::inner_product(dev_ptr, dev_ptr + 10, dev_ptr, 0.0f);
  }

 {
  //CHECK: dpct::device_vector<double> t;
  //CHECK-NEXT: std::for_each( oneapi::dpl::execution::make_device_policy(q_ct1), t.begin(), t.end(), absolute_value<double>());
  thrust::device_vector<double> t;
  thrust::for_each( t.begin(), t.end(), absolute_value<double>());
 }

 {
  //CHECK: int min = std::min(1, 2);
  //CHECK-NEXT: int max = std::max(1, 2);
  int min = thrust::min(1, 2);
  int max = thrust::max(1, 2);
 }

 {
  //CHECK: dpct::device_vector<int> a, b, c;
  //CHECK-NEXT: dpct::sort(oneapi::dpl::execution::make_device_policy(q_ct1), a.begin(), b.end(), c.begin());
  thrust::device_vector<int> a, b, c;
  thrust::sort_by_key(a.begin(), b.end(), c.begin());
 }

 {
  const int N = 1000;
  //CHECK: dpct::device_vector<float> t1(N);
  //CHECK-NEXT: dpct::device_vector<float> t2(N);
  //CHECK-NEXT: dpct::device_vector<float> t3(N);
  //CHECK-NEXT: std::transform(oneapi::dpl::execution::make_device_policy(q_ct1), t1.begin(), t1.end(), t2.begin(), t3.begin(), std::divides<float>());
  //CHECK-NEXT: std::transform(oneapi::dpl::execution::make_device_policy(q_ct1), t1.begin(), t1.end(), t2.begin(), t3.begin(), std::multiplies<float>());
  //CHECK-NEXT: std::transform(oneapi::dpl::execution::make_device_policy(q_ct1), t1.begin(), t1.end(), t2.begin(), t3.begin(), std::plus<float>());
  thrust::device_vector<float> t1(N);
  thrust::device_vector<float> t2(N);
  thrust::device_vector<float> t3(N);
  thrust::transform(t1.begin(), t1.end(), t2.begin(), t3.begin(), thrust::divides<float>());
  thrust::transform(t1.begin(), t1.end(), t2.begin(), t3.begin(), thrust::multiplies<float>());
  thrust::transform(t1.begin(), t1.end(), t2.begin(), t3.begin(), thrust::plus<float>());
 }

 {
    //CHECK: dpct::device_vector<int> data(4);
    //CHECK-NEXT: std::transform(oneapi::dpl::execution::make_device_policy(q_ct1), data.begin(), data.end(), dpct::make_constant_iterator(10), data.begin(), std::divides<int>());
    thrust::device_vector<int> data(4);
    thrust::transform(data.begin(), data.end(), thrust::make_constant_iterator(10), data.begin(), thrust::divides<int>());
 }

 {
    //CHECK: std::tuple<int, const char *> t(13, "foo");
    //CHECK-NEXT: std::cout << "The 1st value of t is " << std::get<0>(t) << std::endl;
    //CHECK-NEXT: auto ret = std::make_tuple(3, 4);
    thrust::tuple<int, const char *> t(13, "foo");
    std::cout << "The 1st value of t is " << thrust::get<0>(t) << std::endl;
    auto ret = thrust::make_tuple(3, 4);
 }

 {
  //CHECK: dpct::device_vector<int> int_in(3);
  //CHECK-NEXT: dpct::device_vector<float> float_in(3);
  //CHECK-NEXT: auto ret = oneapi::dpl::make_zip_iterator(int_in.begin(), float_in.begin());
  //CHECK-NEXT: auto arg = std::make_tuple(int_in.begin(), float_in.begin());
  //CHECK-NEXT: auto ret_1 = oneapi::dpl::make_zip_iterator(std::get<0>(arg), std::get<1>(arg));
  thrust::device_vector<int> int_in(3);
  thrust::device_vector<float> float_in(3);
  auto ret = thrust::make_zip_iterator(thrust::make_tuple(int_in.begin(), float_in.begin()));
  auto arg = thrust::make_tuple(int_in.begin(), float_in.begin());
  auto ret_1 = thrust::make_zip_iterator(arg);
 }

 {
   // CHECK: int a;
   // CHECK-NEXT: double b;
   // CHECK-NEXT: std::tie(a, b) = std::make_tuple(1, 2.0);
   int a;
   double b;
   thrust::tie(a, b) = thrust::make_tuple(1, 2.0);
 }

 {
  //CHECK: int x =  137;
  //CHECK-NEXT: int y = -137;
  //CHECK-NEXT: oneapi::dpl::maximum<int> mx;
  //CHECK-NEXT: int value = mx(x,y);
  int x =  137;
  int y = -137;
  thrust::maximum<int> mx;
  int value = mx(x,y);
 }

 {
  int data[10];
  //CHECK: dpct::device_pointer<int> begin = dpct::get_device_pointer(&data[0]);
  //CHECK-NEXT: dpct::device_pointer<int> end=begin + 10;
  //CHECK-NEXT: bool h_result = std::transform_reduce(oneapi::dpl::execution::make_device_policy(q_ct1), begin, end, 0, std::plus<bool>(), isfoo_test<int>());
  //CHECK-NEXT: bool h_result_1 = std::transform_reduce(oneapi::dpl::execution::seq, begin, end, 0, std::plus<bool>(), isfoo_test<int>());
  thrust::device_ptr<int> begin = thrust::device_pointer_cast(&data[0]);
  thrust::device_ptr<int> end=begin + 10;
  bool h_result = thrust::transform_reduce(begin, end, isfoo_test<int>(), 0, thrust::plus<bool>());
  bool h_result_1 = thrust::transform_reduce(thrust::seq, begin, end, isfoo_test<int>(), 0, thrust::plus<bool>());

 }

{
  struct my_math
  {
  //CHECK: int operator()(const int &r) const{ return r+1;}
  __host__ __device__ int operator()(const int &r) const{ return r+1;}
  };

  int *dev_a = NULL, *dev_b = NULL;
  cudaStream_t stream;
  my_math c;
  //CHECK: std::transform(oneapi::dpl::execution::make_device_policy(*stream),dev_a,dev_a + 10,dev_b,c);
  thrust::transform(thrust::cuda::par.on(stream),dev_a,dev_a + 10,dev_b,c);
}

{
  int values[10] = {1, 0, 1, 0, 1, 0, 1, 0, 1, 0};
  thrust::device_vector<int> d_values(values, values + 10);
  int map[10] = {0, 2, 4, 6, 8, 1, 3, 5, 7, 9};
  thrust::device_vector<int> d_map(map, map + 10);
  thrust::device_vector<int> d_output(10);
  // CHECK: dpct::gather(oneapi::dpl::execution::make_device_policy(q_ct1), d_map.begin(), d_map.end(), d_values.begin(), d_output.begin());
  // CHECK-NEXT: dpct::gather(oneapi::dpl::execution::make_device_policy(q_ct1), d_map.begin(), d_map.end(), d_values.begin(), d_output.begin());
  thrust::gather(d_map.begin(), d_map.end(), d_values.begin(), d_output.begin());
  thrust::gather(thrust::device, d_map.begin(), d_map.end(), d_values.begin(),d_output.begin());
}

{
  int values[10] = {1, 0, 1, 0, 1, 0, 1, 0, 1, 0};
  thrust::host_vector<int> h_values(values, values + 10);
  int map[10] = {0, 2, 4, 6, 8, 1, 3, 5, 7, 9};
  thrust::host_vector<int> h_map(map, map + 10);
  thrust::host_vector<int> h_output(10);

  // CHECK: dpct::gather(oneapi::dpl::execution::seq, h_map.begin(), h_map.end(), h_values.begin(), h_output.begin());
  // CHECK-NEXT: dpct::gather(oneapi::dpl::execution::seq, h_map.begin(), h_map.end(), h_values.begin(), h_output.begin());
  thrust::gather(thrust::seq, h_map.begin(), h_map.end(), h_values.begin(),h_output.begin());
  thrust::gather(h_map.begin(), h_map.end(), h_values.begin(),h_output.begin());
}

{
  int values[10] = {1, 0, 1, 0, 1, 0, 1, 0, 1, 0};
  thrust::device_vector<int> d_values(values, values + 10);
  int map[10] = {0, 5, 1, 6, 2, 7, 3, 8, 4, 9};
  thrust::device_vector<int> d_map(map, map + 10);
  thrust::device_vector<int> d_output(10);

  // CHECK: dpct::scatter(oneapi::dpl::execution::make_device_policy(q_ct1), d_values.begin(), d_values.end(), d_map.begin(), d_output.begin());
  // CHECK-NEXT: dpct::scatter(oneapi::dpl::execution::make_device_policy(q_ct1), d_values.begin(), d_values.end(), d_map.begin(), d_output.begin());
  thrust::scatter(d_values.begin(), d_values.end(), d_map.begin(), d_output.begin());
  thrust::scatter(thrust::device, d_values.begin(), d_values.end(), d_map.begin(), d_output.begin());
}

{
  int values[10] = {1, 0, 1, 0, 1, 0, 1, 0, 1, 0};
  thrust::host_vector<int> h_values(values, values + 10);
  int map[10] = {0, 5, 1, 6, 2, 7, 3, 8, 4, 9};
  thrust::host_vector<int> h_map(map, map + 10);
  thrust::host_vector<int> h_output(10);

  // CHECK: dpct::scatter(oneapi::dpl::execution::seq, h_values.begin(), h_values.end(), h_map.begin(), h_output.begin());
  // CHECK-NEXT: dpct::scatter(oneapi::dpl::execution::seq, h_values.begin(), h_values.end(), h_map.begin(), h_output.begin());
  thrust::scatter(thrust::seq, h_values.begin(), h_values.end(), h_map.begin(), h_output.begin());
  thrust::scatter(h_values.begin(), h_values.end(), h_map.begin(), h_output.begin());
}

{
  const int N = 7;
  int A[N] = {1, 3, 3, 3, 2, 2, 1}; // input keys
  int B[N] = {9, 8, 7, 6, 5, 4, 3}; // input values

  thrust::device_vector<int> d_keys(A, A + N);
  thrust::device_vector<int> d_values(B, B + N);
  thrust::device_vector<int> d_output_keys(N);
  thrust::device_vector<int> d_output_values(N);
  thrust::equal_to<int> binary_pred;

  typedef thrust::pair<thrust::device_vector<int>::iterator,
                       thrust::device_vector<int>::iterator>
      iter_pair;
  thrust::device_vector<iter_pair> new_last_vec(1);
  iter_pair new_last;

  thrust::pair<int *, int *> new_end;

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::make_device_policy(q_ct1), d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin(), binary_pred);
  *new_last_vec.begin() = thrust::unique_by_key_copy(thrust::device, d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin(), binary_pred);

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::make_device_policy(q_ct1), d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin(), binary_pred);
  *new_last_vec.begin() = thrust::unique_by_key_copy(d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin(), binary_pred);

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::make_device_policy(q_ct1), d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin());
  *new_last_vec.begin() = thrust::unique_by_key_copy(d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin());

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::make_device_policy(q_ct1), d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin());
  *new_last_vec.begin() = thrust::unique_by_key_copy(thrust::device, d_keys.begin(), d_keys.end(), d_values.begin(), d_output_keys.begin(), d_output_values.begin());
}

{
  const int N = 7;
  int A[N] = {1, 3, 3, 3, 2, 2, 1}; // input keys
  int B[N] = {9, 8, 7, 6, 5, 4, 3}; // input values

  thrust::host_vector<int> h_keys(A, A + N);
  thrust::host_vector<int> h_values(B, B + N);
  thrust::host_vector<int> h_output_keys(N);
  thrust::host_vector<int> h_output_values(N);
  thrust::equal_to<int> binary_pred;

  typedef thrust::pair<thrust::host_vector<int>::iterator,
                       thrust::host_vector<int>::iterator>
      iter_pair;
  thrust::host_vector<iter_pair> new_last_vec(1);
  iter_pair new_last;

  thrust::pair<int *, int *> new_end;

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::seq, h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin(), binary_pred);
  *new_last_vec.begin() = thrust::unique_by_key_copy(thrust::seq, h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin(), binary_pred);

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::seq, h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin(), binary_pred);
  *new_last_vec.begin() = thrust::unique_by_key_copy(h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin(), binary_pred);

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::seq, h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin());
  *new_last_vec.begin() = thrust::unique_by_key_copy(h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin());

  // CHECK: *new_last_vec.begin() = dpct::unique_copy(oneapi::dpl::execution::seq, h_keys.begin(), h_keys.end(), h_values.begin(), h_output_keys.begin(), h_output_values.begin());
  *new_last_vec.begin() = thrust::unique_by_key_copy(thrust::seq, h_keys.begin(), h_keys.end(), h_values.begin(),h_output_keys.begin(), h_output_values.begin());
}
}

// CHECK: const std::vector<float> transform(
// CHECK-NEXT:     const std::vector<int>& src, size_t width, size_t height, size_t pitch)
// CHECK-NEXT: {
// CHECK-NEXT:     const std::vector<float> result(100, 0);
// CHECK-NEXT:     return result;
// CHECK-NEXT: }
const thrust::host_vector<float> transform(
    const thrust::host_vector<int>& src, size_t width, size_t height, size_t pitch)
{
    const thrust::host_vector<float> result(100, 0);
    return result;
}

// CHECK: template <typename T>
// CHECK-NEXT: const std::vector<float> transformT(
// CHECK-NEXT:     const std::vector<T>& src, size_t width, size_t height, size_t pitch)
// CHECK-NEXT: {
// CHECK-NEXT:     const std::vector<float> result(100, 0);
// CHECK-NEXT:     return result;
// CHECK-NEXT: }
template <typename T>
const thrust::host_vector<float> transformT(
    const thrust::host_vector<T>& src, size_t width, size_t height, size_t pitch)
{
    const thrust::host_vector<float> result(100, 0);
    return result;
}

// CHECK: const dpct::device_vector<float> transform(
// CHECK-NEXT:     const dpct::device_vector<int>& src, size_t width, size_t height, size_t pitch)
// CHECK-NEXT: {
// CHECK-NEXT:     const dpct::device_vector<float> result(100, 0);
// CHECK-NEXT:     return result;
// CHECK-NEXT: }
const thrust::device_vector<float> transform(
    const thrust::device_vector<int>& src, size_t width, size_t height, size_t pitch)
{
    const thrust::device_vector<float> result(100, 0);
    return result;
}

// CHECK: template <typename T>
// CHECK-NEXT: const dpct::device_vector<float> transformT(
// CHECK-NEXT:     const dpct::device_vector<T>& src, size_t width, size_t height, size_t pitch)
// CHECK-NEXT: {
// CHECK-NEXT:     const dpct::device_vector<float> result(100, 0);
// CHECK-NEXT:     return result;
// CHECK-NEXT: }
template <typename T>
const thrust::device_vector<float> transformT(
    const thrust::device_vector<T>& src, size_t width, size_t height, size_t pitch)
{
    const thrust::device_vector<float> result(100, 0);
    return result;
}

void test(){
    // CHECK: const std::vector<float> d_actual;
    const thrust::host_vector<float> d_actual;
    // CHECK: const dpct::device_vector<float> d_actual2;
    const thrust::device_vector<float> d_actual2;
}

struct make_pair_functor
{
  template<typename T1, typename T2>
  __host__ __device__ thrust::pair<T1,T2> operator()(const T1 &x, const T2 &y)
  {
    return thrust::make_pair(x,y);
  } // end operator()()
}; // end make_pair_functor

// CHECK: typedef std::pair<int,int> P;
// CHECK-NEXT: std::pair<int,int> P1;
typedef thrust::pair<int,int> P;
thrust::pair<int,int> P1;

class AbstractInput {
public:
  AbstractInput() {}
  ~AbstractInput() {}

  template <size_t index> int *&getOutputNode() {
   // CHECK:    return *std::get<index>(m_pOutputNodes);
    return *std::get<index>(m_pOutputNodes);
  }

private:
  int *m_pOutputNodes;
};

__global__ void kernel1(){
  int a[10];
  // CHECK:  /*
  // CHECK-NEXT:  DPCT1007:{{[0-9]+}}: Migration of thrust::sort is not supported.
  // CHECK-NEXT:  */
  thrust::sort(thrust::device, a, a + 9);
}
template<typename Itr>
void mysort(Itr Beg, Itr End){
  cudaStream_t s1;
  thrust::host_vector<int> h_vec(10);
  thrust::device_vector<int> d_vec(10);

  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), Beg, End);
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), Beg, End);
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), Beg, End);
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(*s1), Beg, End);
  thrust::sort(Beg, End);
  thrust::sort(thrust::host, Beg, End);
  thrust::sort(thrust::device, Beg, End);
  thrust::sort(thrust::cuda::par.on(s1), Beg, End);

  // CHECK: std::sort(oneapi::dpl::execution::par_unseq, h_vec.begin(), h_vec.end());
  // CHECK: std::sort(h_vec.begin(), h_vec.end());
  thrust::sort(thrust::host, h_vec.begin(), h_vec.end());
  thrust::sort(h_vec.begin(), h_vec.end());

  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(*s1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  thrust::sort(thrust::cuda::par.on(s1), d_vec.begin(), d_vec.end());
  thrust::sort(thrust::device, d_vec.begin(), d_vec.end());
  thrust::sort(d_vec.begin(), d_vec.end());
  thrust::sort(thrust::cuda::par, d_vec.begin(), d_vec.end());
  thrust::sort(thrust::host, d_vec.begin(), d_vec.end());
}


typedef cudaStream_t FooType;
template <typename T> class Container {

public:
  Container(FooType stream) { m_Stream = stream; };
  FooType getStream() const { return m_Stream; }

  FooType m_Stream;
};

struct my_math {
  __host__ __device__ int operator()(int &r) { return r + 1; }
};

template <typename InputType, typename OutputType>
void myfunction(const std::shared_ptr<const Container<InputType>> &inImageData,
                int *dev_a, int *dev_b) {
  // CHECK: std::transform(oneapi::dpl::execution::make_device_policy(*inImageData->getStream()), dev_a, dev_a + 10, dev_b, my_math());
  thrust::transform(thrust::cuda::par.on(inImageData->getStream()), dev_a, dev_a + 10, dev_b, my_math());
}

template <typename InputType, typename OutputType>
void myfunction2(FooType stream, int *dev_a, int *dev_b) {
  // CHECK: std::transform(oneapi::dpl::execution::make_device_policy(*stream), dev_a, dev_a + 10, dev_b, my_math());
  thrust::transform(thrust::cuda::par.on(stream), dev_a, dev_a + 10, dev_b, my_math());
}

int main(void){
  thrust::host_vector<int> h_vec(10);
  thrust::device_vector<int> d_vec(10);
  cudaStream_t s1;

  mysort(h_vec.begin(), h_vec.end());
  mysort(d_vec.begin(), d_vec.end());

  // CHECK: std::sort(oneapi::dpl::execution::par_unseq, h_vec.begin(), h_vec.end());
  // CHECK: std::sort(h_vec.begin(), h_vec.end());
  thrust::sort(thrust::host, h_vec.begin(), h_vec.end());
  thrust::sort(h_vec.begin(), h_vec.end());

  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(*s1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  // CHECK: oneapi::dpl::sort(oneapi::dpl::execution::make_device_policy(q_ct1), d_vec.begin(), d_vec.end());
  thrust::sort(thrust::cuda::par.on(s1), d_vec.begin(), d_vec.end());
  thrust::sort(thrust::device, d_vec.begin(), d_vec.end());
  thrust::sort(d_vec.begin(), d_vec.end());
  thrust::sort(thrust::cuda::par, d_vec.begin(), d_vec.end());
  thrust::sort(thrust::host, d_vec.begin(), d_vec.end());

  return 0;
}