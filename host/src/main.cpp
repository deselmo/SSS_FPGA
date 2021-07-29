#include <cstdio>
#include <cmath>
#include <acl/acl.hpp>

#define BOARDS_FILE_NAME "../assets/boards"

typedef struct __attribute__((packed)) __attribute__((aligned(16))) {
    uint8_t board[9][5];
    uint8_t status;
} task_ddr_t;

enum {
    UNSOLVED = 0,
    SOLVED,
    OUT_OF_MEMORY
};


bool board_import(uint8_t board[9][5], long &id, std::ifstream &is) {
    static long static_id = 0;
    size_t i{0};
    char c;
    std::string tmp;

    id = static_id++;

    while(i<9*9 && is.get(c)) {
        if(c=='\n' || c=='\r' || c==' ') continue;

        if(c == '.')  {
            c = 0;
        } else {
            c-=48;
            if(c != '.' && (c<0 || c>9)) break;
        }

        uint j=i%9;

        if(!(j%2)) {
            board[i/9][j/2] &= 0x0F;
            board[i/9][j/2] |= c << 4;
        } else {
            board[i/9][j/2] &= 0xF0;
            board[i/9][j/2] |= c;
        }
        i++;
    }

    return i==81;
}


void board_print(uint8_t board[9][5]) {
  for(int8_t i=0; i<9; i++) {
        for(int8_t j=0; j<9; j++) {
            printf("%u", !(j%2) ? board[i][j/2] >> 4 : board[i][j/2] & 0x0F);
        }
        printf("\n");
  }
}

bool board_valid(uint8_t board[9][5]) {
    const uint8_t B2SR[9][9] = {
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
    const uint8_t B2SC[9][9] = {
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

    for(int8_t i=0; i<9; i++) {
        bool row[10] = { false };
        bool col[10] = { false };
        bool sub[10] = { false };

        for(int8_t j=0; j<9; j++) {
            int8_t i_;
            int8_t j_;

            i_= i;
            j_= j;
            uint8_t cell_row = !(j_%2) ? board[i_][j_/2] >> 4 : board[i_][j_/2] & 0x0F;
            
            i_ = j;
            j_ = i;
            uint8_t cell_col = !(j_%2) ? board[i_][j_/2] >> 4 : board[i_][j_/2] & 0x0F;

            i_ = B2SR[i][j];
            j_ = B2SC[i][j];

            uint8_t cell_sub = !(j_%2) ? board[i_][j_/2] >> 4 : board[i_][j_/2] & 0x0F;

            if(row[cell_row]) {
                printf("invalid row %d %d\n", (int)i, (int)j);
                return false;
            } else if(col[cell_col]) {
                printf("invalid col %d %d\n", (int)i, (int)j);
                return false;
            } else if(sub[cell_sub]) {
                printf("invalid sub %d %d\n", (int)i, (int)j);
                return false;
            } else {
                row[cell_row] = true;
                col[cell_col] = true;
                sub[cell_sub] = true;
            }
        }
    }

    return true;
}

int main(int argc, char *argv[]) {
    acl::Options options(argc, argv);

    std::string binary_file_name
        = options.has("b")
        ? options.get("b")
        : BINARY_FILE_NAME;

    std::string boards_file_name
        = options.has("boards")
        ? options.get("boards")
        : BOARDS_FILE_NAME;


    std::vector<task_ddr_t> boards; {
        long id;
        task_ddr_t sudoku = {0};
        std::ifstream is_boards(boards_file_name);
        while(board_import(sudoku.board, id, is_boards)) {
            boards.push_back(sudoku);
        }
        is_boards.close();
    }


    acl::Timer timer_bin("Bin loaded");
    cl::Program program = acl::Program(binary_file_name);
    timer_bin.stop();
    printf("%s", timer_bin.output().c_str());


    cl::Event input_event;
    cl::CommandQueue queue_input = acl::queue(true);
    cl::Kernel kernel_input(program, "input");

    cl::Event output_event;
    cl::CommandQueue queue_output = acl::queue(true);
    cl::Kernel kernel_output(program, "output");


    acl::SharedBuffer<task_ddr_t> src(boards.size());
    acl::SharedBuffer<task_ddr_t> dst(boards.size());

    kernel_input.setArg (0, src());
    kernel_output.setArg(0, dst());
    kernel_input.setArg (1, (cl_uint) boards.size());
    kernel_output.setArg(1, (cl_uint) boards.size());


    for(size_t i=0; i<boards.size(); ++i) {
        src[i] = boards[i];
    }

    acl::profile_autorun_kernels(program);
    queue_input.enqueueTask(kernel_input, nullptr, &input_event);
    queue_output.enqueueTask(kernel_output, nullptr, &output_event);
    output_event.wait();
    acl::profile_autorun_kernels(program);

    int error = 0;

    for(size_t i=0; i<boards.size(); ++i) {
        task_ddr_t sudoku = dst[i];

        if(sudoku.status == SOLVED || sudoku.status == UNSOLVED) {
            if(board_valid(sudoku.board)) {
                // printf("%zu valid\n", i);
                // board_print(sudoku.board);
                // printf("\n");
            } else {
                printf("%zu: invalid\n", i);
                board_print(sudoku.board);
                error = 1;
                break;
            }
        } else if(sudoku.status == OUT_OF_MEMORY) {
            printf("%zu: insufficient memory to solve\n", i);
            board_print(sudoku.board);
            error = 1;
            break;
        }

    }

    printf("time: %0.3f ms\n", acl::elapsed(input_event, output_event));

    return error;
}
