#include <utils.cl>

#define NW 4

#define BUFFER_SIZE ((1<<15)/NW)

#define LATENCY_MANAGER 6
#define LATENCY_MEMORY 5
#define LATENCY_SOLVER (50+20)

#define LATENCY_SCHEDULER_IN 5
#define LATENCY_SCHEDULER_OUT 6
#define LATENCY_SCHEDULER ((LATENCY_SCHEDULER_IN )+\
                           (LATENCY_SCHEDULER_OUT)+\
                           (SCHEDULER_N_MID))

#define SCHEDULER_N_MID ((SCHEDULER_N_IN)*(SCHEDULER_N_OUT))



#define STOP_COUNTER_EMULATOR (1<<20)
#define STOP_COUNTER (LATENCY_MANAGER * 2 + \
                     LATENCY_SOLVER      + \
                     LATENCY_SCHEDULER   + \
                     LATENCY_MEMORY)

#define SCHEDULER_N_IN  NW
#define SCHEDULER_N_OUT NW

typedef uint8_t value_t[9][5];

typedef struct {
    value_t value;
    uint8_t status;
} task_t;

typedef struct __attribute__((packed)) __attribute__((aligned(16))) {
    task_t task;
} task_ddr_t;


typedef uint __attribute__((__ap_int(4))) cell_t;
typedef uint __attribute__((__ap_int(9))) bitset_t;

typedef bitset_t board_bs_t[9][9];

enum {
    UNSOLVED = 0,
    SOLVED,
    OUT_OF_MEMORY
};

typedef struct {
    uint n_out;
    task_t sudoku;
    cell_t values[9];
    uint min_i;
    uint min_j;
} solver_data_t;


channel __attribute__((depth(1))) task_t ch_input;
channel __attribute__((depth(1))) task_t ch_output;

// #define ch_memory_in ch_memory_out
channel __attribute__((depth(1))) task_t ch_memory_in[NW];
// channel __attribute__((depth(1))) task_t ch_memory_out[NW];
#define ch_memory_out buffer
channel __attribute__((depth(BUFFER_SIZE))) task_t buffer[NW];

channel __attribute__((depth(1))) task_t ch_solver_in[NW];
#define ch_solver_out ch_memory_in
channel __attribute__((depth(1))) uint8_t ch_memory_oom[NW];

#define ch_manager_problem ch_input
#define ch_manager_solution ch_output
#define ch_manager_in ch_memory_out
#define ch_manager_out ch_scheduler_in
channel __attribute__((depth(1))) uint8_t ch_manager_oom;

channel __attribute__((depth(1))) task_t ch_scheduler_in[NW];
#define ch_scheduler_out ch_solver_in
channel __attribute__((depth(1))) task_t ch_scheduler_mid[SCHEDULER_N_MID];



__kernel void input(__global const task_ddr_t * restrict src, uint size) {
    for(uint i=0; i<size; ++i) {
        task_t task = src[i].task;
        write_channel_intel(ch_input, task);
    }
}

__kernel void output(__global task_ddr_t * restrict dst, uint size) {
    for(uint i=0; i<size; ++i) {
        task_t task = read_channel_intel(ch_output);
        dst[i].task = task;
    }
}


__attribute__((autorun))
__attribute__((num_compute_units(1)))
__attribute__((max_global_work_dim(0)))
__kernel void manager() {
    task_t solution = {0};
    solution.status = UNSOLVED;

    uint count = 0;

    bool have[NW];
    task_t task[NW];

    #pragma unroll
    for(uint i=0; i<NW; ++i) {
        have[i] = false;
    }

    have[0] = true;
    task[0] = read_channel_intel(ch_manager_problem);

    do {
        bool reset = false;
        bool OOM = true;

        #pragma unroll
        for(uint i=0; i<NW; ++i) {
            if(!have[i]) {
                task[i] = read_channel_nb_intel(ch_manager_in[i], &have[i]);
                if(have[i] && !solution.status && task[i].status) {
                    solution = task[i];
                }
            }

            if(have[i]) {
                reset |= true;
            }

            if(have[i]) {
                if(!solution.status) {
                    have[i] = ! write_channel_nb_intel(ch_manager_out[i], task[i]);
                } else {
                    have[i] = false;
                }
            }
        }

        read_channel_nb_intel(ch_manager_oom, &OOM);

        if(!solution.status) {
            if(OOM) {
                solution.status = OUT_OF_MEMORY;
            }
        }

        if(!reset) {
            count++;
        } else {
            count = 0;
        }
    }
    #ifdef ARCH_EMULATOR
    while(count < STOP_COUNTER_EMULATOR);
    #else
    while(count < STOP_COUNTER);
    #endif

    write_channel_intel(ch_manager_solution, solution);
}


__attribute__((autorun))
__attribute__((num_compute_units(NW)))
__attribute__((max_global_work_dim(0)))
__kernel void solver() {
    uint cid = get_compute_id(0);

    const cell_t B2SR[9][9] = {
        {0, 0, 0, 1, 1, 1, 2, 2, 2},
        {0, 0, 0, 1, 1, 1, 2, 2, 2},
        {0, 0, 0, 1, 1, 1, 2, 2, 2},
        {3, 3, 3, 4, 4, 4, 5, 5, 5},
        {3, 3, 3, 4, 4, 4, 5, 5, 5},
        {3, 3, 3, 4, 4, 4, 5, 5, 5},
        {6, 6, 6, 7, 7, 7, 8, 8, 8},
        {6, 6, 6, 7, 7, 7, 8, 8, 8},
        {6, 6, 6, 7, 7, 7, 8, 8, 8}
    };
    const cell_t B2SC[9][9] = {
        {0, 1, 2, 0, 1, 2, 0, 1, 2},
        {3, 4, 5, 3, 4, 5, 3, 4, 5},
        {6, 7, 8, 6, 7, 8, 6, 7, 8},
        {0, 1, 2, 0, 1, 2, 0, 1, 2},
        {3, 4, 5, 3, 4, 5, 3, 4, 5},
        {6, 7, 8, 6, 7, 8, 6, 7, 8},
        {0, 1, 2, 0, 1, 2, 0, 1, 2},
        {3, 4, 5, 3, 4, 5, 3, 4, 5},
        {6, 7, 8, 6, 7, 8, 6, 7, 8}
    };

    const uint DR = 20;

    solver_data_t data[DR+1] = {0};

    while(true) {
        solver_data_t __attribute__((register)) curr = data[0];
        bool one_out = false;

        if(curr.n_out == 0) {
            bool have;
            task_t task = read_channel_nb_intel(ch_solver_in[cid], &have);

            if(have) {
                curr.sudoku = task;
                curr.sudoku.status = UNSOLVED;

                board_bs_t board_bs={0}, miss={0}, miss_count={0};

                bool solved = true;
                bool drop = false;

                #pragma unroll
                for(uint i=0; i<9; ++i) {
                    #pragma unroll
                    for(uint j=0; j<9; ++j) {
                        cell_t cell = !(j%2) 
                                    ? curr.sudoku.value[i][j/2] >> 4
                                    : curr.sudoku.value[i][j/2] & 0x0F;

                        if(!cell) {
                            solved &= false;
                        }

                        board_bs[i][j] = cell ? 1 << (cell-1) : 0;
                    }
                }

                if(solved) {
                    curr.sudoku.status = SOLVED;
                }

                bitset_t rows_or[9]={0},
                            cols_or[9]={0},
                            subs_or[9]={0};
                {
                    bitset_t rows_xor[9]={0},
                                cols_xor[9]={0},
                                subs_xor[9]={0};

                    #pragma unroll
                    for(uint i=0; i<9; ++i) {
                        #pragma unroll
                        for(uint j=0; j<9; ++j) {
                            rows_or[i] |= board_bs[i][j];
                            cols_or[i] |= board_bs[j][i];
                            subs_or[i] |= board_bs[B2SR[i][j]][B2SC[i][j]];

                            rows_xor[i] ^= board_bs[i][j];
                            cols_xor[i] ^= board_bs[j][i];
                            subs_xor[i] ^= board_bs[B2SR[i][j]][B2SC[i][j]];

                            if(rows_or[i] != rows_xor[i]
                            || cols_or[i] != cols_xor[i]
                            || subs_or[i] != subs_xor[i]) {
                                drop = true;
                            }
                        }
                    }
                }

                if(!drop) {
                    bitset_t min_count_bs=0;

                    #pragma unroll
                    for(uint i=0; i<9; ++i) {
                        #pragma unroll
                        for(uint j=0; j<9; ++j) {
                            if(!board_bs[i][j]) {
                                bitset_t tmp = ~(rows_or[i] | cols_or[j] | subs_or[B2SR[i][j]]);

                                miss[i][j] = tmp;

                                #pragma unroll
                                for(uint k=0; k<9; ++k) {
                                    if(tmp & (((bitset_t) 1) << k)) {
                                        miss_count[i][j] = miss_count[i][j] ? miss_count[i][j] << 1 : 1;
                                    }
                                }
                                drop |= !miss_count[i][j];
                            }
                        }
                    }

                    if(!drop) {
                        #pragma unroll
                        for(uint i=0; i<9; ++i) {
                            #pragma unroll
                            for(uint j=0; j<9; ++j) {
                                min_count_bs |= miss_count[i][j];
                            }
                        }

                        min_count_bs &= -min_count_bs;

                        #pragma unroll
                        for(uint i=0; i<9; ++i) {
                            #pragma unroll
                            for(uint j=0; j<9; ++j) {
                                if(min_count_bs == miss_count[i][j]) {
                                    curr.min_i = i;
                                    curr.min_j = j;
                                }
                            }
                        }


                        bitset_t miss_min_value;

                        #pragma unroll
                        for(uint i=0; i<9; ++i) {
                            #pragma unroll
                            for(uint j=0; j<9; ++j) {
                                if(i == curr.min_i && j == curr.min_j) {
                                    miss_min_value = miss[i][j];
                                }
                            }
                        }

                        uint min_count = 0;

                        #pragma unroll
                        for(uint k=0; k<9; ++k) {
                            if(miss_min_value & (((bitset_t) 1) << k)) {
                                curr.values[min_count++] = k+1;
                            }
                        }

                        #pragma unroll
                        for(uint i=0; i<9; ++i) {
                            #pragma unroll
                            for(uint j=0; j<9; ++j) {
                                if(miss_count[i][j] == 1) {
                                    #pragma unroll
                                    for(uint k=0; k<9; ++k) {
                                        if(miss[i][j] & (((bitset_t) 1) << k)) {
                                            if(!(j%2)) {
                                                curr.sudoku.value[i][j/2] |= (k+1) << 4;
                                            } else {
                                                curr.sudoku.value[i][j/2] |= k+1;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        curr.n_out = curr.sudoku.status == SOLVED ? 1 : min_count;
                        one_out = curr.n_out == 1;
                    }
                }
            }
        }

        if(curr.n_out > 0) {
            uint k = --curr.n_out;
            #pragma unroll
            for(uint i=0; i<9; ++i) {
                #pragma unroll
                for(uint j=0; j<9; ++j) {
                    if(one_out) {}
                    else if(i==curr.min_i && j==curr.min_j) {
                        if(!(j%2)) {
                            curr.sudoku.value[i][j/2]
                                = (curr.sudoku.value[i][j/2] & 0x0F)
                                | (uint8_t) curr.values[k] << 4;
                        } else {
                            curr.sudoku.value[i][j/2]
                                = (curr.sudoku.value[i][j/2] & 0xF0)
                                | (uint8_t) curr.values[k];
                        }
                    }
                }
            }

            write_channel_intel(ch_solver_out[cid], curr.sudoku);
        }

        #pragma unroll
        for(uint i=0; i<DR; ++i) {
            data[i] = data[i+1];
        }
        data[DR] = curr;
    }
}



__attribute__((autorun))
__attribute__((num_compute_units(SCHEDULER_N_IN)))
__attribute__((max_global_work_dim(0)))
__kernel void scheduler_in() {
    uint cid = get_compute_id(0);

    task_t task;
    bool have = false;

    while(true) {
        if(!have) {
            task = read_channel_nb_intel(ch_scheduler_in[cid], &have);
        }

        #pragma unroll
        for(uint i=0; i<SCHEDULER_N_OUT; ++i) {
            if(have) {
                have = ! write_channel_nb_intel(ch_scheduler_mid[cid*SCHEDULER_N_OUT + i], task);
            }
        }
    }
}


__attribute__((autorun))
__attribute__((num_compute_units(SCHEDULER_N_OUT)))
__attribute__((max_global_work_dim(0)))
__kernel void scheduler_out() {
    uint cid = get_compute_id(0);

    task_t task;
    bool have = false;

    while(true) {
        #pragma unroll
        for(uint i=0; i<SCHEDULER_N_IN; ++i) {
            if(!have) {
                task = read_channel_nb_intel(ch_scheduler_mid[cid + i*SCHEDULER_N_OUT], &have);
            }
        }

        if(have) {
            have = ! write_channel_nb_intel(ch_scheduler_out[cid], task);
        }
    }
}



__attribute__((autorun))
__attribute__((num_compute_units(NW)))
__attribute__((max_global_work_dim(0)))
__kernel void memory_in() {
    uint cid = get_compute_id(0);

    task_t task;
    bool have = false;

    while(true) {
        if(!have) {
            task = read_channel_nb_intel(ch_memory_in[cid], &have);
        }

        if(have) {
            have = ! write_channel_nb_intel(buffer[cid], task);
            if(have) {
                write_channel_nb_intel(ch_memory_oom[cid], 0);
            }
        }
    }
}


__attribute__((autorun))
__attribute__((num_compute_units(1)))
__attribute__((max_global_work_dim(0)))
__kernel void memory_oom() {
    bool OOM;

    while(true) {
        OOM = true;

        #pragma unroll
        for(uint i=0; i<NW; ++i) {
            bool oom;
            read_channel_nb_intel(ch_memory_oom[i], &oom);
            OOM &= oom;
        }

        if(OOM) {
            write_channel_intel(ch_manager_oom, 0);
        }
    }
}
