# color_config.nu

export def define_color_config [] {
    {
        range: white
        shape_list: cyan
        bool: light_cyan
        string: white
        shape_signature: green
        shape_literal: blue
        shape_bool: light_cyan
        list: white
        shape_directory: cyan

        search_result: {
            fg: white
            bg: red
        }

        shape_custom: green
        shape_block: blue
        cell-path: white
        binary: white
        shape_external: cyan
        row_index: green
        block: white
        shape_closure: green
        glob: cyan
        shape_datetime: cyan
        closure: green
        filesize: cyan
        shape_operator: yellow
        float: white
        shape_string: green
        shape_internalcall: cyan
        shape_raw_string: light_purple
        record: white
        int: white
        nothing: white

        shape_matching_brackets: {
            attr: u
        }

        shape_external_resolved: light_yellow
        shape_range: yellow
        shape_binary: purple
        shape_externalarg: green
        shape_table: blue
        shape_variable: purple
        shape_flag: blue
        shape_nothing: light_cyan
        shape_pipe: purple
        shape_filepath: cyan

        leading_trailing_space_bg: {
            attr: n
        }

        shape_vardecl: purple
        shape_float: purple
        shape_string_interpolation: cyan

        shape_garbage: {
            fg: white
            bg: red
        }

        duration: white
        empty: blue
        shape_keyword: cyan
        datetime: purple
        shape_int: purple
        header: green
        separator: white
        shape_glob_interpolation: cyan
        shape_match_pattern: green
        shape_redirection: purple
        shape_globpattern: cyan
        hints: dark_gray
        shape_record: cyan
    }
}
