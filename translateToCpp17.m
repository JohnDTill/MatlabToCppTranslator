%% MATLAB to C++17 Translator
% This function translates code from the MATLAB language into C++17 code.
% This is useful to distribute and speedup code. MATLAB functions can be
% transpiled to MATLAB executable (MEX) functions for convenient use in the
% MATLAB interpreter.
%
% While MATLAB Coder targets low-level code to remain relevant for embedded
% systems applications, this translator targets C++17 in the hopes of
% generating readable output code. For this reason we avoid any code 
% optimizations- the hope is that the C++ compiler will perform these where
% possible.
%
% The translator is written in MATLAB since it assumes primary fluency in
% that language. However, a faster translator may be obtained by
% "bootstrapping", that is translating the translator into a MEX function.

function translateToCpp17()
    %DO THIS - figure out structure of parameters
    M_filename = 'testFunc.m';
    cpp_filename = 'testFunc.cpp';
    mex_filename = 'mexFunc';
    uses_mathematically_correct_notation = true;
    resizing_disallowed = true;
    write_to_workspace = true;
    
    %%
    % There are several questions we need to answer as we parse the source
    % code so that we will know what capabilities to include in the
    % generated C++ code.
    references_ans = false;
    ans_start = 0;
    has_ignored_outputs = false;
    
    %% File Input
    % This is pretty self-explanatory; the source file is read into a
    % string. If the file is empty, we abort with a warning so as not to
    % interfere with any batch compilation jobs.
    
    %Parse the file name, allowing the user to neglect the extension
    split = strsplit(M_filename,'.');
    if length(split) == 1
        extensionless_name = M_filename;
        M_filename = [extensionless_name, '.m'];
    elseif length(split) == 2
        extensionless_name = split{1};
    else
        warning(char(strcat("'", M_filename, "' is not a valid file name.")));
        return
    end

    %Load the file into a string 
    text = fileread(M_filename); %This may fail with an appropriate error message
    total = length(text);

    %Abort on empty files
    if total==0
        warning(char(strcat("Attempted to translate file '", M_filename, "', which is completely empty.")));
        return
    end

    
    %% Documentation Scanner
    % This section pulls the documentation from the top of the file, i.e.
    % whatever you would see when you type 'help -filename-' in MATLAB.
    %
    % The rules for documentation are fairly simple:
    % each documentation line must begin with a simple comment; block
    % comments and comments after line continuations do not count as
    % documentation lines. Whitespace lines are allowed before the
    % documentation, but any whitespace lines after the documentation has
    % started terminate the documentation. In other words:
    
    % -Start of file-
    % This would be documentation.
    % So would this.
    %{
    The line above is too, but this block comment breaks the documentation.
    %}
    ... This line continuation comment would break it too.
        
    % So would a line of whitespace.
        
    %%
    % Got it? Let's implement it! We start with some variables to track our
    % position in the document and to a function to move forward:
    
    curr = 1; %Current character index
    c = text(curr); %Current character
    line = 1; %Used to report any parsing errors.
    
    function advanceScanner()
        curr = curr + 1;
        if curr <= total
            c = text(curr);
        end
    end

    %%
    % Now we write the code to parse the documentation. First we ignore all
    % whitespace before the documentation.

    while (isspace(c) || c==newline || c==char(13)) && curr <= total
        if c==newline || c==char(13)
            line = line + 1;
            if c==char(13) && curr+1<=total && text(curr+1)==newline
                advanceScanner();
            end
        end

        advanceScanner();
    end
    
    %%
    % There is an edge case to consider; if this is a function file, the
    % documentation may appear after the function headline.
    
    start = 1;
    if curr+7 <= total && strcmp(text(curr:curr+7),'function')
        %Advance past function headline (to newline)
        while ~( c==newline || c==char(13) ) && curr <= total
            if c=='.' && curr+2<=total && text(curr+1)=='.' && text(curr+2)=='.'
                %Line continuation
                while ~( c==newline || c==char(13) ) && curr <= total
                    advanceScanner();
                end
                
                line = line + 1;
                if c==char(13) && curr+1<=total && text(curr+1)==newline
                    advanceScanner();
                end
            end
            
            advanceScanner();
        end
        
        line = line + 1;
        if c==char(13) && curr+1<=total && text(curr+1)==newline
            advanceScanner();
        end
        advanceScanner();
        start = curr;
        
        while (isspace(c) || c==newline || c==char(13)) && curr <= total
            if c==newline || c==char(13)
                line = line + 1;
                if c==char(13) && curr+1<=total && text(curr+1)==newline
                    advanceScanner();
                end
            end

            advanceScanner();
        end
    end
    
    %%
    % Now we can parse the comments as documentation until there is a
    % break.

    %Take in comments as long as each line starts with a '%'.
    %There may be whitespace before the '%', but each line must have a '%'.
    has_doc = false;
    while (c=='%' || (isspace(c) && c~=newline && c~=char(13))) && curr <= total
        if c =='%'
            has_doc = true;

            %Keep going until a newline is consumed
            while c~=newline && c ~=char(13) && curr <= total
                advanceScanner();
            end
            
            final = curr-1;
            
            if c==char(13) && curr+1<=total && text(curr+1)==newline
                advanceScanner();
            end

            line = line + 1;
            advanceScanner();
        end
    end

    if curr > total
        warning(char(strcat("Attempted to translate file '", M_filename, "' with no code.")))
        return
    end

    if has_doc
        documentation = text(start:final);
    end
    
    %%
    % That's it! We can include this documentation in the translated file,
    % and for MEX files we can create a seperate .m file that only holds
    % the documentation so that users can still use the 'help' command. It
    % would be good to add a notice that the file has been compiled in the
    % _highly unlikely_ event that we introduce a bug in the translation
    % process.
    %
    % One last thing: it turns out that stopping the documentation on a
    % block comment such as
    
    % Doc
    %{
    Opening line of block comment is last line of Doc.
    %}
    
    %%
    % and then correctly handling the block comment is difficult. Instead,
    % we'll just reset the position for the scanner and reparse any comments.
    curr = 1;
    line = 1;

    
    %% Code Scanner
    % The scanner makes a single iteration over the source code to group
    % characters into meaningful constructs. Symbols are particularly easy
    % to recognize. Strings, identifiers (names of variables and functions),
    % and numeric literals (numbers) are more difficult to recognize since
    % they may be comprised of a long character array.
    %
    % See [1] for MATLAB's rules for characters.
    % A list of reserved keywords can be obtained by typing 'iskeyword'. We
    % will have to make sure we do not generate C++ reserved keywords, e.g.
    % 'new = 5', but that can be accomplished by modifying variable names.
    %
    % The rules for commenting turn out to be complicated since block comments
    % have a complex syntax. The opening '%{' must be a line having only
    % whitespace, and the closing '%}' must be the same.
    % We hack our way around this for the scanner by including a local
    % variable:
    clean_line = true;
    %%
    % This will be set false whenever we encounter a non-whitespace
    % character, and true when we encounter a new line.
    % 
    % The rules for char arrays are also complicated since the ' symbol can
    % indicate a complex conjugate of a matrix.
    % Thus we introduce another hack:
    uptick_is_char_array = true;
    % As long as we're looking at keywords, there is an issue we can
    % settle. There are two possible syntaxes for writing a function in
    % MATLAB. Including the closing 'end' keyword is optional. For
    % instance, the following is valid:
    
    %{
        function result = add5(num)
            result = add2(num) + 3;
        end
        function result = add2(num)
            result = num + 2;
        end
    %}
    %%
    % And the following is also valid:
    
    %{
        function result = add5(num)
            result = add2(num) + 3;
        function result = add2(num)
            result = num + 2;
    %}
    %%
    % Fortunately, the function syntax must be consistent accross the
    % entire file. As we search for keywords, we will count the number of
    % functions, number of other opening keywords, and the number of 'end'
    % occurences. This gives us an easy way to determine the function
    % syntax in use.
    num_function = 0;
    num_open = 0;
    num_end = 0;
    num_global = 0;
    %%
    % But there is another caveat. The keyword 'end' can be used in a
    % matrix access, e.g. 'I = eye(3); e3 = I(:,end)'. Fortunately 'end' as
    % a statement must always occur with a balanced number of parenthesis,
    % and 'end' as an expression must always occur with an imbalance. Thus
    % we also count the number of parenthesis open:
    num_parenthesis_open = 0;
    
    %%
    % Also, it will be useful to count the numbers of identifiers for later
    % use with the symbol table.
    num_identifiers = 0;
    %%
    % With the preliminary matters settled, we introduce a few functions
    % for the scanner:
    
    function TF = isAtEnd()
        TF = curr > total;
    end
    
    function TF = s_match(char)
        TF = (c==char);
    end

    function TF = s_peek(char)
        if curr >= total
            TF = false;
        else
            TF = (text(curr+1)==char);
        end
    end
    
    %%
    % Next we define the token types. We enumerate them as integers:
    
    EOF = 0;
    STRING = 1;
    MULTIPLY = 2;
    DIVIDE = 3;
    BACK_DIVIDE = 4;
    SCALAR = 5;
    IDENTIFIER = 6;
    NEWLINE = 7;
    FUNCTION = 8;
    ADD = 9;
    SUBTRACT = 10;
    EQUALS = 11;
    LEFT_PAREN = 12;
    RIGHT_PAREN = 13;
    SEMICOLON = 14;
    END = 15;
    COMMENT = 16;
    FUN_HANDLE = 17;
    LEFT_BRACKET = 18;
    RIGHT_BRACKET = 19;
    LEFT_BRACE = 20;
    RIGHT_BRACE = 21;
    WHILE = 22;
    FOR = 23;
    IF = 24;
    AND = 27;
    OR = 28;
    SHORT_AND = 29;
    SHORT_OR = 30;
    TILDE = 31;
    NOT_EQUAL = 32;
    GREATER = 33;
    GREATER_EQUAL = 34;
    LESS = 35;
    LESS_EQUAL = 36;
    POWER = 37;
    SWITCH = 39;
    CASE = 40;
    ELSEIF = 41;
    BREAK = 42;
    TRY = 43;
    CATCH = 44;
    OTHERWISE = 45;
    RETURN = 46;
    BLOCK_COMMENT = 47;
    EQUALITY = 48;
    COMMA = 49;
    CLASS = 50;
    CONTINUE = 51;
    GLOBAL = 52;
    PARFOR = 53;
    PERSISTENT = 54;
    SPMD = 55;
    ELSE = 56;
    COMP_CONJ = 57;
    CHAR_ARRAY = 58;
    ELEM_MULT = 59;
    ELEM_DIV = 60;
    ELEM_BACKDIV = 61;
    ELEM_POWER = 62;
    TRANSPOSE = 63;
    DOT = 64;
    OS_CALL = 65;
    META_CLASS = 66;
    LINE_CONTINUATION = 67;
    COLON = 68;
    
    %%
    % With the token types defined, it is time to ask ourselves: what is a
    % token? It might often be a class or a struct. However, those are some
    % of the more difficult features to implement, so using classes or
    % structs would make it harder to finally bootstrap the translator.
    % Instead, we'll use a matrix where each column is a token. The rows
    % correspond to the type, the line number, the starting position of the
    % lexeme in the text, and the ending position. That's
    %
    % token = [type; line; start; final]
    %
    % We don't know how many tokens we will end up with, but the simple
    % lazy answer is to allocate the maximum possible length.
    
    %Make the token matrix with the maximum possible length
    tokens = zeros(4,total+1);
    num_tokens = 0;
    
    function buildToken(type,line,start,final)
        num_tokens = num_tokens+1;
        tokens(:,num_tokens) = [type; line; start; final];
    end

    function build1CharToken(type)
        buildToken(type,line,curr,curr);
    end

    function build2CharToken(type)
        buildToken(type,line,curr,curr+1);
    end

    function last_token = prev()
        if num_tokens > 0
            last_token = tokens(1,num_tokens);
        else
            last_token = -1;
        end
    end

    %%
    % Finally, we can start implementing the scanner.

    %Parse the file into tokens
    while ~isAtEnd()
        c = text(curr);

        if s_match(newline) || s_match(char(13)) %Newline / carriage return
            build1CharToken(NEWLINE);
            line = line + 1;
            clean_line = true;
            uptick_is_char_array = true;
            if s_match(char(13)) && s_peek(newline)
                %Handle '\r\n' as one token
                curr = curr + 1;
            end
        elseif isspace(c) %Whitespace
            %Do nothing
            uptick_is_char_array = true;
        elseif s_match("%") %Comment
            comment();
            uptick_is_char_array = true;
        else
            %Any other characters mean there is not a block comment on this
            %line.
            clean_line = false;
            
            if s_match('.')
                if curr < total && text(curr+1) >= '0' && text(curr+1) <= '9'
                    %Starting decimals with '0' is good practice!
                    number();
                    uptick_is_char_array = false;
                elseif s_peek('*')
                    build2CharToken(ELEM_MULT);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                elseif s_peek('/')
                    build2CharToken(ELEM_DIV);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                elseif s_peek('\')
                    build2CharToken(ELEM_BACKDIV);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                elseif s_peek('^')
                    build2CharToken(ELEM_POWER);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                elseif s_peek("'")
                    build2CharToken(TRANSPOSE);
                    curr = curr + 1;
                    uptick_is_char_array = false;
                elseif curr+2 <= total && text(curr+1)=='.' && text(curr+2)=='.'
                    %Line continuation - ignore everything until newline
                    %Note: MATLAB allows comments after line continuations.
                    %
                    %      Technically you can do some crazy things here.
                    %      This is a valid assignment:
                    %      a = 5 + ...
                    %      %{
                    %
                    %      %}
                    %      10;
                    %      This is too complicated for the scanner, but
                    %      the parser could handle such edge cases.
                    start = curr + 3;
                    
                    while c~=newline && c~=char(13) && curr <= total
                        c = text(curr);
                        curr = curr + 1;
                    end
                    
                    curr = curr - 1;
                    buildToken(LINE_CONTINUATION,line,start,curr);
                else
                    build1CharToken(DOT);
                end
            elseif s_match('+')
                build1CharToken(ADD);
                uptick_is_char_array = true;
            elseif s_match('-')
                build1CharToken(SUBTRACT);
                uptick_is_char_array = true;
            elseif s_match('*')
                build1CharToken(MULTIPLY);
                uptick_is_char_array = true;
            elseif s_match('/')
                build1CharToken(DIVIDE);
                uptick_is_char_array = true;
            elseif s_match('\')
                build1CharToken(BACK_DIVIDE);
                uptick_is_char_array = true;
            elseif s_match("!")
                %The ! operator reads the whole line as a system command,
                %no quotes required.
                start = curr + 1;
                while ~(s_peek(newline) || s_peek(char(13)))
                    if curr < total
                        curr = curr + 1;
                    else
                        break
                    end
                end
                buildToken(OS_CALL,line,start,curr);
                uptick_is_char_array = true;
            elseif s_match("?")
                build1CharToken(META_CLASS);
                uptick_is_char_array = true;
            elseif s_match('^')
                build1CharToken(POWER);
                uptick_is_char_array = true;
            elseif s_match("'")
                if uptick_is_char_array
                    string();
                else
                    build1CharToken(COMP_CONJ);
                end
            elseif s_match(',')
                if prev()==COMMA
                    error(char(strcat("Expression or statement is incorrect--possibly unbalanced (, {, or [ at line ", num2str(tokens(2,num_tokens)), '.')));
                end
                build1CharToken(COMMA);
                uptick_is_char_array = true;
            elseif s_match('=')
                if s_peek('=')
                    build2CharToken(EQUALITY);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                else
                    build1CharToken(EQUALS);
                    uptick_is_char_array = true;
                end
            elseif s_match('(')
                build1CharToken(LEFT_PAREN);
                uptick_is_char_array = true;
                num_parenthesis_open = num_parenthesis_open + 1;
            elseif s_match(')')
                build1CharToken(RIGHT_PAREN);
                uptick_is_char_array = false;
                num_parenthesis_open = num_parenthesis_open - 1;
            elseif s_match('[')
                build1CharToken(LEFT_BRACKET);
                uptick_is_char_array = true;
            elseif s_match(']')
                build1CharToken(RIGHT_BRACKET);
                uptick_is_char_array = false;
            elseif s_match('{')
                build1CharToken(LEFT_BRACE);
                uptick_is_char_array = true;
            elseif s_match('}')
                build1CharToken(RIGHT_BRACE);
                uptick_is_char_array = false;
            elseif s_match(';')
                build1CharToken(SEMICOLON);
                uptick_is_char_array = true;
            elseif s_match(':')
                build1CharToken(COLON);
                uptick_is_char_array = true;
            elseif s_match('@')
                build1CharToken(FUN_HANDLE);
            elseif s_match('&')
                if s_peek('&')
                    build2CharToken(SHORT_AND);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                else
                    build1CharToken(AND);
                    uptick_is_char_array = true;
                end
            elseif s_match('|')
                if s_peek('|')
                    build2CharToken(SHORT_OR);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                else
                    build1CharToken(OR);
                    uptick_is_char_array = true;
                end
            elseif s_match('~')
                if s_peek('=')
                    build2CharToken(NOT_EQUAL);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                else
                    build1CharToken(TILDE);
                    uptick_is_char_array = true;
                end
            elseif s_match('>')
                if s_peek('=')
                    build2CharToken(GREATER_EQUAL);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                else
                    build1CharToken(GREATER);
                    uptick_is_char_array = true;
                end
            elseif s_match('<')
                if s_peek('=')
                    build2CharToken(LESS_EQUAL);
                    curr = curr + 1;
                    uptick_is_char_array = true;
                else
                    build1CharToken(LESS);
                    uptick_is_char_array = true;
                end
            elseif s_match('"') %String ("'" may be a string or transposition)
                string();
                uptick_is_char_array = true;
            else
                if c >= '0' && c <= '9'
                    number();
                    uptick_is_char_array = false;
                elseif (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    identifierOrKeyword();
                    uptick_is_char_array = false;
                else
                    error(char(strcat("The character '", c, "' generated a syntax error on line ", num2str(line), ".")))
                end
            end
        end
        
        curr = curr + 1;
    end
    
    %Finish the token stream with an "End of File" token.
    build1CharToken(EOF);
    
    %%
    % We define some of the more complicated scanner rules below:
    
    function comment()
        start = curr + 1;

        %The check for multi-line comments may traverse whitespace
        if clean_line && s_peek("{")
            %Potential multi-line comment
            %There must be only whitespace until a newline
            if curr+2 > total
                error(char(strcat("Unterminated block comment on line ", num2str(line), ".")))
            end

            curr = curr+2;
            c = text(curr);

            consumeBlockCommentWhitespace(line);

            if c==newline || c==char(13)
                blockComment();
                return
            end
        end
        
        simpleComment();
    end

    function simpleComment()
        while c~=newline && c~=char(13) && curr <= total
            c = text(curr);
            curr = curr + 1;
        end

        if curr > total
            curr = curr-1;
        else
            curr = curr - 2;
        end

        buildToken(COMMENT,line,start,curr);
    end

    %%
    % It seems like half our effort in the scanner is spent on handling
    % block comments. Well, there's one more thing we haven't considered
    % yet: _they nest_. We won't worry about having seperate tokens for
    % nested comments, but we will track the nesting level to make sure we
    % exit the outermost block comment at the right spot.

    function blockComment()
        start_line = line;
        start = curr + 1;
        
        block_comment_level = 1;

        %Must be terminated by:
        % \n whitespace* %} whitespace* (\n | EOF)
        while block_comment_level > 0
            %Consume leading whitespace
            consumeBlockCommentWhitespace(start_line);

            %The ending line cannot start with text
            if c~=newline && c~=char(13) && c~="%"
                goToNextBlockCommentLine(start_line);
            end

            if c==newline || c==char(13)
                line = line + 1;
                curr = curr + 1;
                if curr > total
                        error(char(strcat("Unterminated block comment starting on line ", num2str(start_line), ".")))
                end
                c = text(curr);
            end

            if s_match("%") && s_peek('}')
                %Potential end, consume whitespace
                if curr+2 > total
                    block_comment_level = block_comment_level - 1;
                    curr = curr + 2; %Should end three ahead
                else
                    curr = curr + 2;
                    c = text(curr);
                    while isspace(c) && ~(c==newline || c==char(13))
                        curr = curr + 1;
                        if curr > total
                            break
                        end
                        c = text(curr);
                    end

                    if curr > total || c==newline || c==char(13)
                        block_comment_level = block_comment_level - 1;
                    end
                end
            elseif s_match("%") && s_peek('{')
                %Potential nested level, consume whitespace
                if curr+2 > total
                    error(char(strcat("Unterminated block comment starting on line ", num2str(start_line), ".")))
                else
                    curr = curr + 2;
                    c = text(curr);
                    consumeBlockCommentWhitespace(start_line);

                    if curr > total || c==newline || c==char(13)
                        block_comment_level = block_comment_level + 1;
                    end
                end
            else
                %Consume text until newline
                goToNextBlockCommentLine(start_line);
            end
        end
        
        curr = curr - 1;

        buildToken(BLOCK_COMMENT,start_line,start,curr-3);
    end

    function consumeBlockCommentWhitespace(start_line)
        while isspace(c) && ~(c==newline || c==char(13))
            curr = curr + 1;
            if curr > total
                error(char(strcat("Unterminated block comment starting on line ", num2str(start_line), ".")))
            end
            c = text(curr);
        end
    end

    function goToNextBlockCommentLine(start_line)
        while c~=newline && c~=char(13)
            curr = curr + 1;
            if curr > total
                error(char(strcat("Unterminated block comment starting on line ", num2str(start_line), ".")))
            end
            c = text(curr);
        end
    end

    function string()
        type = c; %Must be terminated by same symbol
        if curr == total
            error(char(strcat("A string on line ", num2str(line), " is not closed.")))
        end
        curr = curr + 1;
        start = curr;
        c = text(curr);

        exit = false;

        while ~exit
            while c~=type
                if s_match(newline) || s_match(char(13)) %Newline / carriage return
                    error(char(strcat("A string on line ", num2str(line), " is not closed.")))
                end
                curr = curr + 1;
                if curr > total
                    break
                end
                c = text(curr);
            end

            %Allow escape quotes "hello""world" -> hello"world
            if ~s_peek(type)
                exit = true;
            end
        end

        % The " symbol produces a string whereas
        % the ' symbol produces a char array.
        if type=='"'
            buildToken(STRING,line,start,curr-1);
        else
            buildToken(CHAR_ARRAY,line,start,curr-1);
        end
    end

    function number()
        start = curr;

        %Accept numbers, periods, 'e', and 'e-'
        while ((c >= '0' && c <= '9') || ...
                (c == '.') || ...
                (c == 'e'))
            
            if curr > total
                break
            end
            
            c = text(curr);
            
            if s_match('.') && (curr >= total || text(curr+1) < '0' || text(curr+1) > '9')
                %Cannot end on a decimal point, e.g. 10.*20 should not be
                %parsed as 10. * 20
                
                c = '!'; %Hack to exit the loop
            end
            
            if s_match('e') && s_peek('-')
                %allow negative exponentials,
                %e.g. 1e-10
                curr = curr + 1;
            end
            
            curr = curr + 1;
        end
        if curr > total && (c >= '0' && c <= '9')
            curr = curr - 1;
        else
            curr = curr - 2; %the while loop overreaches by 1
        end

        buildToken(SCALAR,line,start,curr);
    end

    %%
    % We need to think about how we recognize keywords. Building a lookup
    % table would require at least the use of cells, which again isn't
    % ideal from the perspective of wanting to bootstrap with a limited
    % feature set. We will use a trie instead; it takes some effort and
    % too many lines of code, but it's fast to run. Also, don't forget we
    % resolve the function syntax here.

    function identifierOrKeyword()
        start = curr;

        %Accept letters, numbers, and underscore
        while ((c >= 'a' && c <= 'z') || ...
                (c >= 'A' && c <= 'Z') || ...
                (c >= '0' && c <= '9') || ...
                (c == '_')) && curr <= total
            c = text(curr);
            curr = curr + 1;
        end
        if curr <= total
            curr = curr - 2; %the while loop overreaches by 2
        else
            if ((c >= 'a' && c <= 'z') || ...
                (c >= 'A' && c <= 'Z') || ...
                (c >= '0' && c <= '9') || ...
                (c == '_'))
                curr = curr - 1; %Unless it hits the end
            else
                curr = curr - 2;
            end
        end

        %Look for matching keywords
        lexeme = text(start:curr);
        len = curr-start+1;
        
        if len==2
            if strcmp(lexeme,"if")
                buildToken(IF,line,start,curr);
                num_open = num_open + 1;
                return
            end
        elseif len==3
            c = lexeme(1);
            if c=='a'
                if strcmp(lexeme(2:3),'ns')
                    references_ans = true;
                    ans_start = start;
                end
            elseif c=='e'
                if strcmp(lexeme(2:3),"nd")
                    buildToken(END,line,start,curr);
                    if num_parenthesis_open == 0
                        num_end = num_end + 1;
                    end
                    return
                end
            elseif c=='f'
                if strcmp(lexeme(2:3),"or")
                    buildToken(FOR,line,start,curr);
                    num_open = num_open + 1;
                    return
                end
            elseif c=='t'
                if strcmp(lexeme(2:3),"ry")
                    buildToken(TRY,line,start,curr);
                    num_open = num_open + 1;
                    return
                end
            end
        elseif len==4
            c = lexeme(1);
            if c=='c'
                if strcmp(lexeme(2:4),"ase")
                    buildToken(CASE,line,start,curr);
                    return
                end
            elseif c=='e'
                if strcmp(lexeme(2:4),"lse")
                    buildToken(ELSE,line,start,curr);
                    return
                end
            elseif c=='s'
                if strcmp(lexeme(2:4),"pmd")
                    buildToken(SPMD,line,start,curr);
                    num_open = num_open + 1;
                    return
                end
            end
        elseif len==5
            c = lexeme(1);
            if c=='b'
                if strcmp(lexeme(2:5),"reak")
                    buildToken(BREAK,line,start,curr);
                    return
                end
            elseif c=='c'
                if strcmp(lexeme(2:5),"atch")
                    buildToken(CATCH,line,start,curr);
                    return
                end
            elseif c=='w'
                if strcmp(lexeme(2:5),"hile")
                    buildToken(WHILE,line,start,curr);
                    num_open = num_open + 1;
                    return
                end
            end
        elseif len==6
            c = lexeme(1);
            if c=='e'
                if strcmp(lexeme(2:6),"lseif")
                    buildToken(ELSEIF,line,start,curr);
                    return
                end
            elseif c=='g'
                if strcmp(lexeme(2:6),"lobal")
                    buildToken(GLOBAL,line,start,curr);
                    num_global = num_global + 1;
                    return
                end
            elseif c=='p'
                if strcmp(lexeme(2:6),"arfor")
                    buildToken(PARFOR,line,start,curr);
                    num_open = num_open + 1;
                    return
                end
            elseif c=='r'
                if strcmp(lexeme(2:6),"eturn")
                    buildToken(RETURN,line,start,curr);
                    return
                end
            elseif c=='s'
                if strcmp(lexeme(2:6),"witch")
                    buildToken(SWITCH,line,start,curr);
                    num_open = num_open + 1;
                    return
                end
            end
        elseif len==8
            c = lexeme(1);
            if c=='c'
                c = lexeme(2);
                if c=='l'
                    if strcmp(lexeme(3:8),"assdef")
                        buildToken(CLASS,line,start,curr);
                        num_open = num_open + 1;
                        return
                    end
                elseif c=='o'
                    if strcmp(lexeme(3:8),"ntinue")
                        buildToken(CONTINUE,line,start,curr);
                        return
                    end
                end
            elseif c=='f'
                if strcmp(lexeme(2:8),"unction")
                    buildToken(FUNCTION,line,start,curr);
                    num_function = num_function + 1;
                    return
                end
            end
        elseif len==9
            if strcmp(lexeme,"otherwise")
                buildToken(OTHERWISE,line,start,curr);
                return
            end
        elseif len==10
            if strcmp(lexeme,"persistent")
                buildToken(PERSISTENT,line,start,curr);
                return
            end
        end

        %Default to identifier
        buildToken(IDENTIFIER,line,start,curr);
        num_identifiers = num_identifiers + 1;
    end

    %%
    % And with the script part of the scanner implemented above, we can
    % analyze the results of our keyword counting.
    
    if num_open == num_end
        functions_have_end = false;
    elseif num_open+num_function == num_end
        functions_have_end = true;
    else
        error(char(strcat("Wrong number of ENDs in '", M_filename, "'.",...
            " Refer to the MATLAB editor for further detail.")))
        %I.e. "Make sure your code runs before you translate it, you slob."
    end

    %%
    % Okay, I believe we have implemented full coverage of the MATLAB
    % language for the scanner! It would be a feat if the parser ever
    % achieves full coverage, but at least we are DONE with the scanner.
    %
    % As a consequence of how we implemented the scanner, we already have a
    % variable 'num_tokens' ready for use in the parser.
    
    
    %% Building a Parse Tree
    % Now we need to think about how to implement the parse tree. We can
    % use indices of a matrix to emulate pointers in MATLAB, so we store
    % parse nodes in a matrix, similar to how were stored in tokens a
    % vector. We do not know how many columns the matrix should have, so
    % we will over-allocate using the number of tokens.
    %
    % The first row will be the type of node. Statement blocks, parameter
    % lists, and argument lists have arbitrarily many elements. Fortunately
    % no node will belong in two lists, so we can encode these lists as
    % linked lists in the second row. The meaning of the other
    % entries in a column depends on the specific node type. Also, since
    % some of the links may be null, we introduce the NONE variable.
    
    NONE = -1; %In place of null
    nodes = NONE*ones(20,2*num_tokens); %DO THIS - size everything up correctly
    num_nodes = 0;
    
    NODE_TYPE = 1;
    LIST_LINK = 2;
    LINE = 15;
    
    %%
    % As long as we're building the parse tree, we can start annotating it
    % with type and size information.
    DATA_TYPE = 16;
    ROWS = 17;
    COLS = 18;
    CAST_TYPE = 19;
    IMPLICIT_CAST = 20;
    
    %%
    % We define the following types:
    NA = 0;
    
    %STRING = 1; %Defined earlier
    INTEGER = 2;
    REAL = 3;
    BOOLEAN = 4;
    CHAR = 5;
    CELL = 6;
    DYNAMIC = 7;
    
    NUM_TYPES = 7;
    
    function string = getTypeString(node)
        data_type = nodes(DATA_TYPE,node);
        string = typeToString(data_type);
    end

    function string = getCastTypeString(node)
        data_type = nodes(CAST_TYPE,node);
        if data_type==NONE
            string = 'none';
        else
            string = typeToString(data_type);
        end
    end
    
    function string = typeToString(data_type)        
        if data_type==INTEGER
            string = 'int';
        elseif data_type==REAL
            string = 'double';
        elseif data_type==BOOLEAN
            string = 'bool';
        elseif data_type==STRING
            string = 'std::string';
        elseif data_type==CHAR
            string = 'char';
        elseif data_type==CELL
            string = 'cell';
        elseif data_type==FUNCTION
            string = 'FUN';
        elseif data_type==NA
            string = 'N/A';
        elseif data_type==DYNAMIC
            string = 'Matlab::DynamicType';
        else
            string = '???';
        end
    end
    
    %%
    % Now we define functions for the parser:
    
    function num = plusplus_num_nodes()
        num_nodes = num_nodes + 1;
        num = num_nodes;
    end

    function link(predecessor, successor)
        nodes(LIST_LINK,predecessor) = successor;
    end
    
    %%
    % Some of the token types will map directly to node types (e.g.
    % ADDITION or SCALAR), but we also need to define some new types.
    
    BLOCK = -1;
    GROUPING = -4;
    NOT = -5;
    UNARY_MINUS = -6;
    INPUT_LIST = -7;
    OUTPUT_LIST = -8;
    RANGE = -9;
    STEPPED_RANGE = -10;
    CALL = -11;
    ARG_LIST = -12;
    CALL_STMT = -13;
    VERTICAT = -14;
    HORIZCAT = -15;
    EMPTYMAT = -16;
    IGNORED_OUTPUT = -17;
    UNARYCELL = -18;
    VERTICELL = -19;
    HORIZCELL = -20;
    EMPTYCELL = -21;
    CELL_CALL = -22;
    LAMBDA = -23;
    FUNCTION_LAMBDA = -24;
    EXPR_STMT = -25;
    FUN_CALL = -26;
    MATRIX_ACCESS = -27;
    OUT_ARG_LIST = -28;
    FUN_IDENTIFIER = -29;
    
    %%
    % Now we can think about what the nodes should look like. Generally the
    % integer elements of the node are "pointers", although they can have
    % other meanings. For instance, the comment and string nodes have
    % integers for the start and end positions in the text.
    
    FIRST_BLOCK_STATEMENT = 3;
    function id = createBlock(first_block_statement)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = BLOCK;
        nodes(FIRST_BLOCK_STATEMENT,id) = first_block_statement;
        nodes(DATA_TYPE,id) = NA;
    end

    FUN_NAME = 3;
    FUN_OUTPUT = 4;
    FUN_INPUT = 5;
    FUN_BODY = 6;
    function id = createFun(name,output,input,body)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = FUNCTION;
        nodes(FUN_NAME,id) = name;
        nodes(FUN_OUTPUT,id) = output;
        nodes(FUN_INPUT,id) = input;
        nodes(FUN_BODY,id) = body;
        nodes(DATA_TYPE,id) = FUNCTION;
    end

    FIRST_PARAMETER = 3;
    function id = createParameterList(type,head)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = type;
        nodes(FIRST_PARAMETER,id) = head;
        nodes(DATA_TYPE,id) = NA;
    end

    LHS = 3;
    RHS = 4;
    VERBOSITY = 5;
    program_prints_out = false;
    
    function id = createAssignment(lhs,rhs,verbosity)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = EQUALS;
        nodes(LHS,id) = lhs;
        nodes(RHS,id) = rhs;
        nodes(VERBOSITY,id) = verbosity;
        nodes(DATA_TYPE,id) = NA;
        
        if verbosity
            program_prints_out = true;
        end
    end

    function id = createCallStmt(name,out_list,arg_list,verbosity)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = CALL_STMT;
        nodes(LHS,id) = out_list;
        nodes(RHS,id) = arg_list;
        nodes(VERBOSITY,id) = verbosity;
        nodes(6,id) = name;
        nodes(DATA_TYPE,id) = NA;
    end

    function id = createTernary(type,expr1,expr2,expr3)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = type;
        nodes(3,id) = expr1;
        nodes(4,id) = expr2;
        nodes(5,id) = expr3;
    end

    function id = createBinary(type,left_expr,right_expr)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = type;
        nodes(LHS,id) = left_expr;
        nodes(RHS,id) = right_expr;
        
        if type==HORIZCELL || type==VERTICELL
            nodes(DATA_TYPE,id) = CELL;
        elseif type==EQUALITY || type==NOT_EQUAL || type==GREATER || ...
                type==GREATER_EQUAL || type==LESS || type==LESS_EQUAL ||...
                type==AND || type==SHORT_AND || type==OR || ...
                type==SHORT_OR
            nodes(DATA_TYPE,id) = BOOLEAN;
        end
    end

    UNARY_CHILD = 3;
    function id = createUnary(type,expr)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = type;
        nodes(UNARY_CHILD,id) = expr;
        if type==NOT
            nodes(DATA_TYPE,id) = BOOLEAN;
        elseif type==UNARYCELL
            nodes(DATA_TYPE,id) = CELL;
        end
        nodes(ROWS,id) = nodes(ROWS,expr);
        nodes(COLS,id) = nodes(COLS,expr);
    end

    function id = createScalar()
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = SCALAR;
        start = tokens(3,curr-1);
        final = tokens(4,curr-1);
        value_string = text(start:final);
        value = str2double(value_string);
        nodes(3,id) = value;
        if mod(value,1)==0
            nodes(DATA_TYPE,id) = INTEGER;
        else
            nodes(DATA_TYPE,id) = REAL;
        end
        nodes(ROWS,id) = 1;
        nodes(COLS,id) = 1;
    end

    function id = createTokenNode(type)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = type;
    end

    function id = createTextNode(type, has_data_type)
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = type;
        nodes(3:4,id) = tokens(3:4,curr-1);
        nodes(LINE,id) = tokens(2,curr-1);
        if type==STRING
            nodes(DATA_TYPE,id) = STRING;
            nodes(ROWS,id) = 1;
            nodes(COLS,id) = 1;
        elseif type==CHAR_ARRAY
            nodes(DATA_TYPE,id) = CHAR;
            nodes(ROWS,id) = 1;
            nodes(COLS,id) = tokens(4,curr-1) - tokens(3,curr-1) + 1;
        end
        
        if ~has_data_type
            nodes(DATA_TYPE,id) = NA;
        end
    end

    function id = createAnsNode()
        id = plusplus_num_nodes();
        nodes(NODE_TYPE,id) = IDENTIFIER;
        nodes(3,id) = ans_start;
        nodes(4,id) = ans_start + 2;
    end

    function Text = readTextNode(id)
        start = nodes(3,id);
        final = nodes(4,id);
        Text = text(start:final);
    end

    %%
    % We'll consider an example to make the parse tree more concrete. For
    % the following code:
    
    %{
        function added = add5( num )
            added = num + 6 - 1;
        end
    %}
    
    %%
    % The parse tree should look like this:
    %%
    % 
    % <<./Fig/add5.PNG>>
    % 
    
    
    %%
    % Now we can focus on building the tree from the token stream.
    % We use an LL(1) recursive-descent
    % parser, which relies on several functions to move through the token
    % stream. This is also where we handle line continuations.
    
    function TF = match(type)
        while type~=LINE_CONTINUATION && match(LINE_CONTINUATION)
            createTextNode(LINE_CONTINUATION, false);
            match(NEWLINE);
        end
        
        TF = (tokens(1,curr) == type);
        if TF
            curr = curr + 1;
        end
    end
    
    function consume(type)
        assert(match(type),...
            char(strcat("Expected ", num2str(type), ...
            " at line " , num2str(tokens(2,curr)), ".")));
    end

    function TF = peek(type)
        index = curr;
        while tokens(NODE_TYPE,index)==LINE_CONTINUATION
            index = index + 1;
            if tokens(NODE_TYPE,index)==NEWLINE
                index = index+1;
            end
        end
        
        TF = (tokens(1,index) == type);
    end

    function TF = peekTwice(type)
        index = curr;
        while tokens(NODE_TYPE,index)==LINE_CONTINUATION
            index = index + 1;
            if tokens(NODE_TYPE,index)==NEWLINE
                index = index+1;
            end
        end
        index = index + 1;
        while tokens(NODE_TYPE,index)==LINE_CONTINUATION
            index = index + 1;
            if tokens(NODE_TYPE,index)==NEWLINE
                index = index+1;
            end
        end
        
        TF = (tokens(1,index) == type);
    end
    
    %% 
    % Before implementing our parser, we should specify MATLAB's grammar,
    % or at least some subset we support. This is potentially complicated
    % since MATLAB's grammar depends on the types of identifiers, e.g.
    % 'someName(end)' is valid if 'someName' is an array, but not if it is
    % a function. To borrow terminology from object-oriented programming,
    % the first pass will use an abstract context-free grammar, and
    % additional passes will resolve the abstract parse nodes.
    %
    % Exactly matching the syntax of matrix concatenation takes some
    % examination. In it's purest form, horizontal concatenation is
    % represented by commas or spaces, e.g. '[1, 2 3]', and vertical
    % concatenation by semicolons or newlines, e.g. '[1; 2 '\n' 3]'.
    % However, a user can type some truly terrible valid syntax. '[1;;1]'
    % is a valid 2x1 array, as well as [1;,1], or even '[1,;,;;,1]'.
    % However, the occurence of two commas adjacent commas '[1;, ,1]' is
    % illegal. It makes our lives considerably easier to prevent adjacent
    % commas with another scanner hack. This way any white space (including
    % semicolons and commas) after a semicolon or newline is irrelevant. It
    % also isn't required to have an item after a seperator, e.g. '[1,]'
    % and '[1;]' are valid expressions.
    %
    % Fortunately, we are killing two
    % birds with one stone since the cell rules are mostly the same. The
    % only difference is that a cell is a cell even when no concatenation
    % takes place. '[5]' is a scalar, but '{5}' is a cell.
    %
    % The grammar should respect MATLAB's operator precedence [2].
    %
    % The supported grammar is given below in Backus–Naur form (BNF):
    
    %{
    script      -> statement* ;
    funFile     -> funDefine (funDefine | whiteSpace)* ;
    statement   -> funDefine
                    | callStmt
                    | assignment
                    | ifStmt
                    | forStmt
                    | whileStmt
                    | 'return'
                    | 'break'
                    | 'continue'
                    | tryStmt
                    | switchStmt
                    | globalStmt
                    | persistStmt
                    | spmdStmt
                    | sysCall
                    | classStmt
                    | exprStmt ;
    funDefine   -> 'function' (outParams '=')? IDENTIFIER inParams terminator+ (block | noEndBlock) ;
    outParams   -> IDENTIFIER | ( '[' (IDENTIFIER (','? IDENTIFIER)*)? ']') ;
    inParams    -> '(' (IDENTIFIER (',' IDENTIFIER)*)? ')' ;
    block       -> statement* + 'end' ;
    noEndBlock  -> statement* (EOF | funDefine) ;
    callStmt    -> (outParams '=')? call terminator+ ;
    assignment  -> member '=' expr terminator+ ;
    ifStmt      -> 'if' expression terminator+ ifblock* ;
    ifblock     -> statement* ('end' | 'elseif' expression ifblock | 'else' block) ;
    forStmt     -> ('for' | 'parfor') assignment block ;
    whileStmt   -> 'while' expression terminator+ block ;
    tryStmt     -> try statement* ('end' | 'catch' IDENTIFIER? block) ;
    switchStmt  -> 'switch' expression ('case' expression terminator+ noEndBlock)* ('otherwise' noEndBlock)? 'end'
    globalStmt  -> 'global' IDENTIFIER+ terminator ;
    persistStmt -> 'persistent' IDENTIFIER+ terminator ;
    spmdStmt    -> spmd block ;
    terminator  -> '\n' | ';' | ',' | COMMENT | EOF ;
    sysCall     -> '!' (anyCharExceptNewline)* ('\n' | EOF);
    whiteSpace  -> COMMENT | BLOCK_COMMENT | LINE_CONTINUATION
                    | '\n' | ';' | ',' ;
    exprStmt    -> expr terminator ;
    classStmt   -> ERROR ;
    
    expr        -> shortOr ;
    shortOr     -> shortAnd ('||' shortAnd)* ;
    shortAnd    -> or ('&&' or)* ;
    or          -> and ('|' and)* ;
    and         -> comparison ('&' comparison)* ;
    comparison  -> range (('<' | '<=' | '>' | '>=' | '==' | '~=') range)* ;
    range       -> addition (':' addition)* ;
    addition    -> multiply (('+' | '-') multiply)* ;
    multiply    -> leftUnary (('*' | '/' | '\' | '.*' | './' | '.\') leftUnary)* ;
    leftUnary   -> ('~' | '-' | '+')* upperRight ;
    upperRight  -> primary (''' | '.'' | ('^' | '.^') primary) ;
    primary     -> member | '(' expr ')' | 'end' | verticat | unarycell | CHAR_ARRAY | STRING | superclass | lambda ;
    member      -> call ('.' call)* ;
    call        -> IDENTIFIER ( ('(' (arg (',' arg)*)? ')') | ('{' (arg (',' arg)*)? '}') )?;
    arg         -> ':' | expr ;
    verticat    -> '[' horizcat ((';' | '\n') whiteSpace* horizcat?)* ']' ;
    horizcat    -> ('~' | expr) (','? ('~' | expr? | (';' | '\n') whiteSpace* horizcat?))* ;
    unarycell   -> '{' verticell '}' ;
    verticell   -> horizcell ((';' | '\n') whiteSpace* horizcell?)* ;
    horizcell   -> expr (','? (expr? | (';' | '\n') whiteSpace* horizcell?))* ;
    superclass  -> '?' IDENTIFIER ;
    lambda      -> '@' (IDENTIFIER | ( inParams expression ))
    
    %}
    
    %%
    % In the context of a call, 'end' may be allowed as a primary. For this
    % reason we track the call level, and allow the use of 'end' if it is
    % greater than zero. We also track other metrics that will help us with
    % the parser and later stages.
    call_level = 0;
    max_nesting_level = 0;
    nesting_level = 0;
    loop_level = 0;
    parfor_level = 0;
    current_loop = NONE;
    global_base = NONE;
    uses_system = false;
    has_multi_output = false;
    
    %%
    % We kick the process off by determining if we are parsing a function or
    % a script. If it is a function, the first meaningful token will be of
    % FUNCTION type. Otherwise, it is a script.
    
    curr = 1;
    parseAllWhitespace();
    
    %Determine if we are translating a script or function
    if curr == length(tokens)
        warning(char(strcat("The file '", M_filename, "' does not have any code.")));
        return
    elseif peek(FUNCTION)
        is_script = false;
        funFile();
    else
        is_script = true;
        script();
    end
    
    %%
    % Now we implement the production rules as a series of functions.
    
    function script()        
        id = statement();
        root = createBlock(id);
        parseAllWhitespace();
        while(~peek(EOF))
            prev_id = id;
            id = statement();
            link(prev_id,id);
            parseAllWhitespace();
        end
    end
    
    function funFile()
        consume(FUNCTION)
        id = fun();
        checkLeadFunctionName(id);
        root = createBlock(id);
        main_func = id;
        
        parseAllWhitespace();
        
        while(~peek(EOF))
            prev_id = id;
            
            consume(FUNCTION)
            id = fun();
            
            link(prev_id, id);
            
            parseAllWhitespace();
        end
    end

    function checkLeadFunctionName(fun_id)
        name_id = nodes(3,fun_id);
        name = readTextNode(name_id);
        
        if ~strcmp(name,extensionless_name)
            warning(char(strcat("Leading function of '", M_filename, ...
                "' is named '", name, "', should be named '", extensionless_name, "'.")));
            
            %This is not a hard error because you may have a misnamed void
            %or varg function which can be run using the UI.
        end
    end

    function id = statement()
        
        
        if match(FUNCTION)
            id = fun();
        elseif peek(IDENTIFIER)
            return_point = curr;
            consume(IDENTIFIER)
            id = member();
            if match(EQUALS)
                id = assignment(id);
            else
                curr = return_point;
                id = exprStmt();
            end
        elseif match(LEFT_BRACKET)
            return_point = curr-1;
            return_nodes = num_nodes;
            id = verticat();
            if match(EQUALS)
                currline = tokens(2,curr);
                consume(IDENTIFIER);
                name = createTextNode(IDENTIFIER, false);
                [first_arg, ~] = convertToOutputArgList(id,currline);
                id = createParameterList(OUT_ARG_LIST,first_arg);
                consume(LEFT_PAREN);
                id = callStmt(name,id);
            else
                curr = return_point;
                num_nodes = return_nodes;
                id = exprStmt();
            end
        elseif match(IF)
            id = ifStmt();
        elseif match(FOR)
            old_loop = current_loop;
            current_loop = FOR;
            loop_level = loop_level + 1;
            id = forStmt(FOR);
            loop_level = loop_level - 1;
            current_loop = old_loop;
        elseif match(PARFOR)
            old_loop = current_loop;
            current_loop = PARFOR;
            parfor_level = parfor_level + 1;
            id = forStmt(PARFOR);
            parfor_level = parfor_level - 1;
            current_loop = old_loop;
        elseif match(WHILE)
            old_loop = current_loop;
            current_loop = WHILE;
            loop_level = loop_level + 1;
            id = whileStmt();
            loop_level = loop_level - 1;
            current_loop = old_loop;
        elseif match(RETURN)
            if current_loop==PARFOR
                error(char(strcat("Return is not allowed in parfor loops. (line ", num2str(tokens(2,curr-1)), ")")));
            end
            id = createTokenNode(RETURN);
        elseif match(BREAK)
            if loop_level==0
                error(char(strcat("A BREAK statement appeared outside of a loop. Use RETURN instead. (line ", num2str(tokens(2,curr-1)), ")")));
            elseif current_loop==PARFOR
                error(char(strcat("Break is not allowed in parfor loops. (line ", num2str(tokens(2,curr-1)), ")")));
            end
            id = createTokenNode(BREAK);
        elseif match(CONTINUE)
            if loop_level + parfor_level ==0
                error(char(strcat("A CONTINUE may only be used within a FOR or WHILE loop. (line ", num2str(tokens(2,curr-1)), ")")));
            end
            id = createTokenNode(CONTINUE);
        elseif match(TRY)
            id = tryStmt();
        elseif match(SWITCH)
            id = switchStmt();
        elseif match(GLOBAL)
            id = globalStmt();
            if global_base==NONE
                global_base = id;
            end
        elseif match(PERSISTENT)
            id = persistStmt();
        elseif match(SPMD)
            id = block();
            nodes(NODE_TYPE,id) = SPMD;
        elseif match(OS_CALL)
            id = systemCall();
        elseif match(CLASS)
            id = classStmt();
        else
            id = exprStmt();
        end
        
        nodes(DATA_TYPE,id) = NA;
    end

    function id = exprStmt()
        expr = expression();
        verbosity = terminator();
        if ~references_ans
            id = createUnary(EXPR_STMT,expr);
        else
            assignee = createAnsNode();
            id = createAssignment(assignee,expr,verbosity);
        end
        nodes(DATA_TYPE,id) = NA;
        nodes(VERBOSITY,id) = verbosity;
        
        program_prints_out = verbosity || program_prints_out;
    end

    %The callStmt output list had to be parsed as a matrix. Now convert it
    %to a list of identifiers, and throw an error if it is ill formed.
    function [first_arg, last_arg] = convertToOutputArgList(id,line)
        type = nodes(NODE_TYPE,id);
        
        if type==HORIZCAT
            lhs = nodes(LHS,id);
            [first_arg, last_arg] = convertToOutputArgList(lhs,line);
            
            rhs = nodes(RHS,id);
            if nodes(NODE_TYPE,rhs)~=IDENTIFIER && nodes(NODE_TYPE,rhs)~=IGNORED_OUTPUT
                error(char(strcat('Invalid output arg list at line ', num2str(line), '.')))
            end
            nodes(LIST_LINK,last_arg) = rhs;
            last_arg = rhs;
        elseif type==IDENTIFIER || type==IGNORED_OUTPUT
            first_arg = id;
            last_arg = first_arg;
            has_ignored_outputs = has_ignored_outputs || (type==IGNORED_OUTPUT);
        elseif type==EMPTYMAT
            error(char(strcat('An array for multiple LHS assignment cannot be empty- at line ', num2str(line), '.')))
        else
            error(char(strcat('Invalid output arg list at line ', num2str(line), '.')))
        end
    end

    function id = callStmt(id,out_list)
        call_level = call_level + 1;
        arg_list = args(RIGHT_PAREN);
        verbosity = terminator();
        id = createCallStmt(id,out_list,arg_list,verbosity);
        call_level = call_level - 1;
    end

    function id = fun()
        nesting_level = nesting_level + 1;
        if nesting_level > max_nesting_level
            max_nesting_level = nesting_level;
        end
        
        if match(LEFT_BRACKET)
            %Output parameter list
            if match(RIGHT_BRACKET)
                %'function [] = name(...)', which is valid
                output_name = NONE;
            else
                consume(IDENTIFIER);
                output_name = createTextNode(IDENTIFIER, true);
                new_name = output_name;
            
                while ~match(RIGHT_BRACKET)
                    old_name = new_name;
                    
                    match(COMMA); %Comma is recommended, but not required
                    consume(IDENTIFIER);
                    new_name = createTextNode(IDENTIFIER, true);
                    
                    link(old_name,new_name);
                    
                    has_multi_output = true;
                end
            end
            
            consume(EQUALS);
            consume(IDENTIFIER);
            name = createTextNode(IDENTIFIER, false);
            
        elseif match(IDENTIFIER)
            %Could be single output param or function name
            if peek(EQUALS)
                %Single output
                output_name = createTextNode(IDENTIFIER, true);
                consume(EQUALS);
                consume(IDENTIFIER);
                name = createTextNode(IDENTIFIER, false);
            else
                %Void function
                name = createTextNode(IDENTIFIER, false);
                output_name = NONE;
            end
        else
            error(char(strcat("Invalid function definition at line ", num2str(tokens(2,curr-1)), ".")));
        end
        
        consume(LEFT_PAREN);
        
        if match(RIGHT_PAREN)
            input_name = NONE;
        else
            consume(IDENTIFIER);
            input_name = createTextNode(IDENTIFIER, true);
            new_name = input_name;
            while ~match(RIGHT_PAREN)
                old_name = new_name;
                
                consume(COMMA);
                consume(IDENTIFIER);
                new_name = createTextNode(IDENTIFIER, true);
                
                link(old_name,new_name);
            end
        end
        
        terminator();
        parseAllWhitespace();
        % Believe it or not, any terminator works.
        % "function helloWorld(), disp('Hello World!'); end"
        % is a valid function.
        
        if functions_have_end
            body = block();
        else
            body = noEndBlock();
        end
        
        input = createParameterList(INPUT_LIST, input_name);
        output = createParameterList(OUTPUT_LIST, output_name);
        
        id = createFun(name, output, input, body);
        nesting_level = nesting_level - 1;
    end

    function id = ifStmt()
        cond = expression();
        terminator();
        [body,else_stmt] = ifBlock();
        if else_stmt == NONE
            id = createBinary(IF,cond,body);
        else
            id = createTernary(IF,cond,body,else_stmt);
        end
    end

    function id = forStmt(type)
        consume(IDENTIFIER);
        iter_name = createTextNode(IDENTIFIER,true);
        consume(EQUALS)
        iterator = assignment(iter_name);
        body = block();
        id = createBinary(type,iterator,body);
    end

    function id = whileStmt()
        cond = expression();
        terminator();
        body = block();
        id = createBinary(WHILE,cond,body);
    end

    function id = tryStmt()
        parseAllWhitespace();
        
        if peek(END) || peek(CATCH)
            first_statement = NONE;
        else
            first_statement = statement();
            id = first_statement;
            parseAllWhitespace();
            
            while ~(peek(END) || peek(CATCH))
                prev_id = id;

                id = statement();
                link(prev_id, id);

                parseAllWhitespace();
            end
            %no terminator necessary after end
        end
        
        try_block = createBlock(first_statement);
        
        if match(END)
            id = createBinary(TRY,try_block,NONE);
        else
            consume(CATCH);
            return_point = curr;
            
            %This rule is particularly dicey since the identifier could be
            %an exception, or it could be the start of an expression
            %statement. We use try/catch and return to handle both.
            if match(IDENTIFIER)
                exception = createTextNode(IDENTIFIER,true);
                try
                    catch_block = block();
                    catch_node = createBinary(CATCH,exception,catch_block);
                    id = createBinary(TRY,try_block,catch_node);
                    return
                catch
                    curr = return_point;
                end
            end
            
            catch_block = block();
            catch_node = createBinary(CATCH,NONE,catch_block);
            id = createBinary(TRY,try_block,catch_node);
        end
    end

    function id = switchStmt()
        start_line = tokens(2,curr-1);
        switch_expr = expression();
        parseAllWhitespace();
        
        if match(CASE)
            child = caseStmt();
            id = createBinary(SWITCH,switch_expr,child);
        elseif match(OTHERWISE)
            child = otherwiseStmt();
            id = createBinary(SWITCH,switch_expr,child);
        else
            consume(END);
            warning(char(strcat("Empty switch statement at line ", num2str(start_line), ".")))
            id = createBinary(SWITCH,switch_expr,NONE);
        end
    end

    function id = caseStmt()
        case_expr = expression();
        terminator();
        
        parseAllWhitespace();
        
        if peek(END) || peek(CASE) || peek(OTHERWISE)
            first_statement = NONE;
        else
            first_statement = statement();
            id = first_statement;
            parseAllWhitespace();
            
            while ~(peek(END) || peek(CASE) || peek(OTHERWISE))
                prev_id = id;

                id = statement();
                link(prev_id, id);

                parseAllWhitespace();
            end
            %no terminator necessary after end
        end
        
        body = createBlock(first_statement);
        
        if match(END)
            id = createTernary(CASE,case_expr,body,NONE);
        elseif match(CASE)
            child = caseStmt();
            id = createTernary(CASE,case_expr,body,child);
        else
            consume(OTHERWISE)
            child = otherwiseStmt();
            id = createTernary(CASE,case_expr,body,child);
        end
    end

    function id = otherwiseStmt()
        id = block();
        nodes(NODE_TYPE,id) = OTHERWISE;
    end

    function id = globalStmt()
        consume(IDENTIFIER);
        first_node = createTextNode(IDENTIFIER,false);
        id = createUnary(GLOBAL,first_node);
        
        next = first_node;
        while match(IDENTIFIER)
            prev = next;
            next = createTextNode(IDENTIFIER,false);
            link(prev,next);
        end
        
        terminator();
    end

    function id = persistStmt()
        if nesting_level==0
            error(char(strcat("A PERSISTENT declaration is only allowed in a function. (line ", num2str(tokens(2,curr-1)), ")")));
        end
        
        consume(IDENTIFIER);
        first_node = createTextNode(IDENTIFIER,false);
        id = createUnary(PERSISTENT,first_node);
        
        next = first_node;
        while match(IDENTIFIER)
            prev = next;
            next = createTextNode(IDENTIFIER,false);
            link(prev,next);
        end
        
        terminator();
    end

    function id = block()
        parseAllWhitespace();
        
        if match(END)
            first_statement = NONE;
        else
            first_statement = statement();
            id = first_statement;
            parseAllWhitespace();
            
            while ~match(END)
                prev_id = id;

                id = statement();
                link(prev_id, id);

                parseAllWhitespace();
            end
            %no terminator necessary after end
        end
        
        id = createBlock(first_statement);
    end

    function [id,else_stmt] = ifBlock()
        parseAllWhitespace();
        
        if peek(END) || peek(ELSEIF) || peek(ELSE)
            first_statement = NONE;
        else
            first_statement = statement();
            id = first_statement;
            parseAllWhitespace();
            
            while ~(peek(END) || peek(ELSEIF) || peek(ELSE))
                prev_id = id;

                id = statement();
                link(prev_id, id);

                parseAllWhitespace();
            end
            %no terminator necessary after end
        end
        
        id = createBlock(first_statement);
        
        if match(ELSEIF)
            else_stmt = ifStmt();
            nodes(NODE_TYPE,else_stmt) = ELSEIF;
            nodes(DATA_TYPE,else_stmt) = NA;
        elseif match(ELSE)
            terminator();
            else_stmt = block();
            nodes(NODE_TYPE,else_stmt) = ELSE;
            nodes(DATA_TYPE,else_stmt) = NA;
        else
            consume(END)
            else_stmt = NONE;
        end
    end

    function id = noEndBlock()
        parseAllWhitespace();
        
        if peek(EOF) || peek(FUNCTION)
            first_statement = NONE;
        else
            first_statement = statement();
            id = first_statement;
            parseAllWhitespace();
            
            while ~(peek(EOF) || peek(FUNCTION))
                prev_id = id;

                id = statement();
                link(prev_id, id);

                parseAllWhitespace();
            end
        end
        
        id = createBlock(first_statement);
    end

    function id = assignment(assignee)
        rhs = expression();
        verbosity = terminator();
        
        id = createAssignment(assignee,rhs,verbosity);
    end

    function id = systemCall()
        id = createTextNode(OS_CALL,false);
        uses_system = true;
    end

    function parseAllWhitespace()
        while curr < length(tokens) && ...
              ( tokens(1,curr) == COMMENT || ...
                tokens(1,curr) == BLOCK_COMMENT || ...
                tokens(1,curr) == LINE_CONTINUATION || ...
                tokens(1,curr) == NEWLINE || ...
                tokens(1,curr) == SEMICOLON || ...
                tokens(1,curr) == COMMA )
            if match(COMMENT)
                createTextNode(COMMENT,false);
            elseif match(BLOCK_COMMENT)
                createTextNode(BLOCK_COMMENT,false);
            elseif match(LINE_CONTINUATION)
                createTextNode(LINE_CONTINUATION,false);
            else
                curr = curr + 1; %skip others
            end
        end
    end

    function verbosity = terminator()
        if match(SEMICOLON)
            verbosity = 0;
        elseif match(COMMENT)
            createTextNode(COMMENT,false);
            verbosity = 1;
        elseif match(NEWLINE) || match(COMMA) || peek(EOF)
            verbosity = 1;
        else
            error(char(strcat("Unexpected MATLAB expression at line ", num2str(tokens(2,curr-1)), ".")));
        end
    end

    function id = classStmt()
        error(char(strcat("Translator does not support classdef at line ", num2str(tokens(2,curr-1)), ". (Parser)")));
    end

    %%
    % The statements are done. Now we write the production rules for
    % expressions.
    
    function id = expression()
        id = shortOr();
    end

    function id = shortOr()
        id = shortAnd();
        
        while match(SHORT_OR)
            rhs = shortAnd();
            id = createBinary(SHORT_OR,id,rhs);
        end
    end

    function id = shortAnd()
        id = or();
        
        while match(SHORT_AND)
            rhs = or();
            id = createBinary(SHORT_AND,id,rhs);
        end
    end

    function id = or()
        id = and();
        
        while match(OR)
            rhs = and();
            id = createBinary(OR,id,rhs);
        end
    end

    function id = and()
        id = comparison();
        
        while match(AND)
            rhs = comparison();
            id = createBinary(AND,id,rhs);
        end
    end

    function id = comparison()
        id = range();
        
        while peek(GREATER) || peek(GREATER_EQUAL) || peek(LESS) || ...
                peek(LESS_EQUAL) || peek(EQUALITY) || peek(NOT_EQUAL)
            if match(GREATER)
                rhs = range();
                id = createBinary(GREATER,id,rhs);
            elseif match(GREATER_EQUAL)
                rhs = range();
                id = createBinary(GREATER_EQUAL,id,rhs);
            elseif match(LESS)
                rhs = range();
                id = createBinary(LESS,id,rhs);
            elseif match(LESS_EQUAL)
                rhs = range();
                id = createBinary(LESS_EQUAL,id,rhs);
           elseif match(EQUALITY)
                rhs = range();
                id = createBinary(EQUALITY,id,rhs);
            else
                consume(NOT_EQUAL)
                rhs = range();
                id = createBinary(NOT_EQUAL,id,rhs);
            end
        end
    end

    function id = range()
        %'2:3:5:7' is not a syntax error, but what does it mean? It turns
        %out that it parsed as '(2:3:5):7'.
        %What about '2:3:5:7:9'? It is parsed as '(2:3:5):7:9', which
        %produces a different result from '((2:3:5):7):9' and
        %'(2:3:5):(7:9)', so the '7' is treated as the increment.
        %'2:3:5:7:9:11' is parsed as '((2:3:5):7:9):11'.
        %By now we can see the pattern; the colon operator is left
        %recursive.
        
        id = addition();
        
        while match(COLON)
            temp = addition();
            
            if ~match(COLON)
                id = createBinary(RANGE,id,temp);
            else
                range_end = addition();
                id = createTernary(STEPPED_RANGE,id,temp,range_end);
            end
        end
    end

    function id = addition()
        id = multiply();
        
        while peek(ADD) || peek(SUBTRACT)
            lhs = id;
            
            if match(ADD)
                rhs = multiply();
                id = createBinary(ADD,lhs,rhs);
            else
                consume(SUBTRACT);
                rhs = multiply();
                id = createBinary(SUBTRACT,lhs,rhs);
            end
        end
    end

    function id = multiply()
        id = leftUnary();
        
        while peek(MULTIPLY) || peek(DIVIDE) || peek(BACK_DIVIDE) || ...
                peek(ELEM_MULT) || peek(ELEM_DIV) || peek(ELEM_BACKDIV)
            lhs = id;
            
            if match(MULTIPLY)
                rhs = leftUnary();
                id = createBinary(MULTIPLY,lhs,rhs);
            elseif match(DIVIDE)
                rhs = leftUnary();
                id = createBinary(DIVIDE,lhs,rhs);
             elseif match(BACK_DIVIDE)
                rhs = leftUnary();
                id = createBinary(BACK_DIVIDE,lhs,rhs);
             elseif match(ELEM_MULT)
                rhs = leftUnary();
                id = createBinary(ELEM_MULT,lhs,rhs);
             elseif match(ELEM_DIV)
                rhs = leftUnary();
                id = createBinary(ELEM_DIV,lhs,rhs);
            else
                consume(ELEM_BACKDIV);
                rhs = leftUnary();
                id = createBinary(ELEM_BACKDIV,lhs,rhs);
            end
        end
    end

    function id = leftUnary()
        if match(TILDE)
            child = leftUnary();
            id = createUnary(NOT,child);
        elseif match(SUBTRACT)
            child = leftUnary();
            id = createUnary(UNARY_MINUS,child);
        elseif match(ADD)
            %Skip over leftUnary plus
            id = leftUnary();
        else
            id = upperRightCorner();
        end
    end

    function id = upperRightCorner()
        id = primary();
        
        while peek(POWER) || peek(ELEM_POWER) || peek(TRANSPOSE) || ...
                peek(COMP_CONJ)
            lhs = id;
            
            if match(POWER)
                rhs = leftUnary();
                id = createBinary(POWER,lhs,rhs);
            elseif match(ELEM_POWER)
                rhs = leftUnary();
                id = createBinary(ELEM_POWER,lhs,rhs);
            elseif match(TRANSPOSE)
                id = createUnary(TRANSPOSE,id);
            else
                consume(COMP_CONJ);
                id = createUnary(COMP_CONJ,id);
            end
        end
    end

    function id = primary()
        if match(SCALAR)
            id = createScalar();
        elseif match(IDENTIFIER)
            id = member();
        elseif match(LEFT_PAREN)
            id = grouping();
        elseif match(LEFT_BRACKET)
            id = verticat();
        elseif match(LEFT_BRACE)
            id = unarycell();
        elseif call_level > 0 && match(END)
            id = createTokenNode(END);
        elseif match(CHAR_ARRAY)
            id = createTextNode(CHAR_ARRAY,true);
        elseif match(STRING)
            id = createTextNode(STRING,true);
        elseif match(META_CLASS)
            consume(IDENTIFIER);
            name = createTextNode(IDENTIFIER,false);
            id = createUnary(META_CLASS,name);
        elseif match(FUN_HANDLE)
            id = lambda();
        else
            error('Unknown parser error')
        end
    end
    
    function id = member()
        id = call();
        
        while match(DOT)
            consume(IDENTIFIER)
            rhs = call();
            id = createBinary(DOT,id,rhs);
        end
    end

    function id = call()
        id = createTextNode(IDENTIFIER,true);
        
        if match(LEFT_PAREN)
            call_level = call_level + 1;
            arg_list = args(RIGHT_PAREN);
            id = createBinary(CALL,id,arg_list);
            call_level = call_level - 1;
        elseif match(LEFT_BRACE)
            call_level = call_level + 1;
            arg_list = args(RIGHT_BRACE);
            id = createBinary(CELL_CALL,id,arg_list);
            call_level = call_level - 1;
        end
    end

    function id = verticat()
        if match(RIGHT_BRACKET)
            id = createTokenNode(EMPTYMAT);
        else
            id = horizcat();

            while match(SEMICOLON) || match(NEWLINE)
                parseAllWhitespace();
                if ~peek(RIGHT_BRACKET)
                    rhs = horizcat();
                    id = createBinary(VERTICAT,id,rhs);
                end
            end
            
            consume(RIGHT_BRACKET)
        end
    end

    function id = horizcat()
        if peek(TILDE) && (peekTwice(COMMA) || peekTwice(RIGHT_BRACKET))
            %Ignored output only works with comma seperator
            id = createTokenNode(IGNORED_OUTPUT);
            match(TILDE);
        else
            id = expression();
        end
        
        while ~(peek(SEMICOLON) || peek(RIGHT_BRACKET))
            match(COMMA); %Comma is not required
            
            if match(SEMICOLON) || match(NEWLINE)
                %Poor syntax vertical concat
                parseAllWhitespace();
                if ~peek(RIGHT_BRACKET)
                    rhs = horizcat();
                    id = createBinary(VERTICAT,id,rhs);
                end
            elseif peek(TILDE) && (peekTwice(COMMA) || peekTwice(RIGHT_BRACKET))
                %Ignored output: '[a,~] = rand()'
                rhs = createTokenNode(IGNORED_OUTPUT);
                id = createBinary(HORIZCAT,id,rhs);
                match(TILDE);
            elseif ~peek(RIGHT_BRACKET)
                %Default
                rhs = expression();
                id = createBinary(HORIZCAT,id,rhs);
            end
        end
    end

    function id = unarycell()
        if match(RIGHT_BRACE)
            id = createTokenNode(EMPTYCELL);
        else
            id = verticell();
            type = nodes(NODE_TYPE,id);
            if ~(type==VERTICELL || type==HORIZCELL)
                id = createUnary(UNARYCELL,id);
            end
            consume(RIGHT_BRACE);
        end
    end

    function id = verticell()
        id = horizcell();

        while match(SEMICOLON) || match(NEWLINE)
            parseAllWhitespace();
            if ~peek(RIGHT_BRACE)
                rhs = horizcell();
                id = createBinary(VERTICELL,id,rhs);
            end
        end
    end

    function id = horizcell()
        id = expression();
        
        while ~(peek(SEMICOLON) || peek(RIGHT_BRACE))
            match(COMMA); %Comma is not required
            
            if match(SEMICOLON) || match(NEWLINE)
                %Poor syntax vertical concat
                parseAllWhitespace();
                if ~peek(RIGHT_BRACE)
                    rhs = horizcell();
                    id = createBinary(VERTICELL,id,rhs);
                end
            elseif ~peek(RIGHT_BRACE)
                %Default
                rhs = expression();
                id = createBinary(HORIZCELL,id,rhs);
            end
        end
    end

    function id = args(terminating_token)
        if ~match(terminating_token)
            if match(COLON)
                head = createTokenNode(COLON);
            else
                head = expression();
            end
            
            id = createParameterList(ARG_LIST,head);
            
            next = head;
            while ~match(terminating_token)
                prev = next;
                
                consume(COMMA);
                if match(COLON)
                    next = createTokenNode(COLON);
                else
                    next = expression();
                end
                
                link(prev,next);
            end
        else
            id = createParameterList(ARG_LIST,NONE);
        end
    end

    function id = grouping()
        child = expression();
        consume(RIGHT_PAREN);
        id = createUnary(GROUPING,child);
    end

    function id = lambda()
        if match(IDENTIFIER)
            name = createTextNode(IDENTIFIER,false);
            id = createUnary(FUNCTION_LAMBDA,name);
        else
            consume(LEFT_PAREN);
        
            if match(RIGHT_PAREN)
                input_name = NONE;
            else
                consume(IDENTIFIER);
                input_name = createTextNode(IDENTIFIER,false);
                new_name = input_name;
                while ~match(RIGHT_PAREN)
                    old_name = new_name;

                    consume(COMMA);
                    consume(IDENTIFIER);
                    new_name = createTextNode(IDENTIFIER,false);

                    link(old_name,new_name);
                end
            end

            input = createParameterList(INPUT_LIST, input_name);
            body = expression();
            id = createBinary(LAMBDA,input,body);
        end
    end

    %%
    % That's it; we have a parse tree! The parser handles every part of the
    % MATLAB language except for classes. The class syntax would be a
    % behemoth to take on, but the problem will always be waiting for
    % another day [3].
    %
    % Now we can move on to analyzing and annotating the tree.
    
    %% Parse Tree Visitor
    % Before we do though, it would be helpful to define a function for
    % traversing the parse tree.
    
    FUN_REF = -50;
    VAR_REF = -51;
    REF = 3;
    
    function traverse(node,parent,preorder,postorder)
        if ~preorder(node,parent)
            return
        end
        
        type = nodes(NODE_TYPE, node);
        
        if type==FUNCTION
            %The arguments need to be nodes
            traverse( nodes(FUN_NAME,node), node, preorder, postorder );
            traverse( nodes(FUN_INPUT,node), node, preorder, postorder );
            traverse( nodes(FUN_OUTPUT,node), node, preorder, postorder );
            traverse( nodes(FUN_BODY,node), node, preorder, postorder );
        elseif type==CALL || type==CELL_CALL || type==FUN_CALL ||...
                type==MATRIX_ACCESS
            traverse( nodes(3,node), node, preorder, postorder );
            traverse( nodes(4,node), node, preorder, postorder );
        elseif type==TRY
            traverse( nodes(LHS,node), node, preorder, postorder );
            if nodes(RHS,node)~=NONE
                traverse( nodes(4,node), node, preorder, postorder );
            end
        elseif type==CATCH
            if nodes(LHS,node)~=NONE
                traverse( nodes(LHS,node), node, preorder, postorder );
            end
            traverse( nodes(RHS,node), node, preorder, postorder );
        elseif type==SWITCH
            traverse( nodes(LHS,node), node, preorder, postorder );
            if nodes(RHS,node)~=NONE
                traverse( nodes(4,node), node, preorder, postorder );
            end
        elseif type==CASE
            traverse( nodes(3,node), node, preorder, postorder );
            traverse( nodes(4,node), node, preorder, postorder );
            if nodes(5,node)~=NONE
                traverse( nodes(5,node), node, preorder, postorder );
            end
        elseif type==CALL_STMT
            traverse( nodes(6,node), node, preorder, postorder );
            if nodes(LHS,node)~=NONE
                traverse( nodes(LHS,node), node, preorder, postorder );
            end
            traverse( nodes(RHS,node), node, preorder, postorder );
        elseif type==INPUT_LIST || type==OUTPUT_LIST || type==ARG_LIST ||...
                type==OUT_ARG_LIST
            elem = nodes(3,node);
            while elem ~= NONE
                traverse(elem,node,preorder,postorder);
                elem = nodes(LIST_LINK,elem);
            end
        elseif type==IF || type==ELSEIF
            traverse( nodes(3,node), node, preorder, postorder );
            traverse( nodes(4,node), node, preorder, postorder );
            if nodes(5,node)~=NONE
                traverse( nodes(5,node), node, preorder, postorder );
            end
        elseif type==BLOCK || type==ELSE || type==SPMD || ...
                type==GLOBAL || type==PERSISTENT || type==OTHERWISE
            visited = nodes(FIRST_BLOCK_STATEMENT,node);
            while visited~=NONE
                traverse(visited,node,preorder,postorder);
                visited = nodes(LIST_LINK,visited);
            end
        elseif type==STEPPED_RANGE
            traverse( nodes(3,node), node, preorder, postorder);
            traverse( nodes(4,node), node, preorder, postorder);
            traverse( nodes(5,node), node, preorder, postorder);
        elseif type == EQUALS || type == ADD || type == SUBTRACT ||...
                type == MULTIPLY || type == DIVIDE || ...
                type == BACK_DIVIDE || type == POWER || ...
                type == ELEM_POWER || ...
                type == ELEM_MULT || type == ELEM_DIV || ...
                type == ELEM_BACKDIV || type == RANGE || ...
                type == GREATER || type == GREATER_EQUAL || ...
                type == LESS || type == LESS_EQUAL || ...
                type == EQUALITY || type == NOT_EQUAL || ...
                type == AND || type == OR || type == SHORT_AND || ...
                type == SHORT_OR || type == VERTICAT || ...
                type == HORIZCAT || type == VERTICELL || ...
                type == HORIZCELL || type == WHILE || type == FOR || ...
                type == PARFOR || type == DOT || type == LAMBDA
            traverse( nodes(LHS,node), node, preorder, postorder);
            traverse( nodes(RHS,node), node, preorder, postorder);
        elseif type == NOT || type == UNARY_MINUS || type == GROUPING ||...
                type == TRANSPOSE || type == COMP_CONJ || ...
                type == UNARYCELL || type == META_CLASS || ...
                type == FUNCTION_LAMBDA
            traverse( nodes(UNARY_CHILD,node), node, preorder, postorder);
        elseif type == EXPR_STMT
            traverse( nodes(3,node), node, preorder, postorder );
        end
        
        postorder(node,parent);
    end

    function advance = NO_PREORDER(node,parent)
        advance = true;
    end

    function NO_POSTORDER(node,parent)
    end

    %%
    % I don't know about you, but staring at our 'nodes' matrix data
    % structure is giving me a headache. Let's create a visitor that
    % outputs .dot graph visualization files so that we can visualize the
    % parse tree.
    
    dot_name = [extensionless_name, '.dot'];
    dot_file = fopen(dot_name,'w');
    fprintf(dot_file,'digraph {\r\n\trankdir=TB\r\n\r\n');
    
    function descend = dotter(node,parent)
        descend = true;
        fprintf(dot_file,'\t');
        fprintf(dot_file,['node_', num2str(node), ' [label="']);
        fprintf(dot_file,getLabel(node));
        fprintf(dot_file,'"]\r\n');
        if parent~=NONE
            fprintf(dot_file,['\tnode_', num2str(parent), ...
                ' -> node_', num2str(node), '\r\n\r\n']);
        end
    end

    function label = getLabel(node)
        type = nodes(NODE_TYPE,node);
        
        if type==FUNCTION
            label = 'FUN';
        elseif type==BLOCK
            label = 'BLOCK';
        elseif type==ADD
            label = '+';
        elseif type==SUBTRACT
            label = '-';
        elseif type==MULTIPLY
            label = '*';
        elseif type==DIVIDE
            label = '/';
        elseif type==BACK_DIVIDE
            label = '\\\\';
        elseif type==IDENTIFIER || type==FUN_IDENTIFIER
            label = readTextNode(node);
        elseif type==CHAR_ARRAY
            label = ['''',readTextNode(node),''''];
        elseif type==STRING
            label = ['\\"',readTextNode(node),'\\"'];
        elseif type==SCALAR
            label = num2str(nodes(3,node));
        elseif type==EQUALS
            label = ['ASSIGN\\nverbosity=',num2str(nodes(VERBOSITY,node))];
        elseif type==INPUT_LIST
            label = 'INPUT';
        elseif type==OUTPUT_LIST
            label = 'OUTPUT';
        elseif type==POWER
            label = '^';
        elseif type==TRANSPOSE
            label = 'TRANSPOSE';
        elseif type==COMP_CONJ
            label = 'COMP_CONJ';
        elseif type==GROUPING
            label = '()';
        elseif type==OS_CALL
            label = ['OS_CALL\\n\\"',readTextNode(node),'\\"'];
        elseif type==NOT
            label = 'NOT';
        elseif type==UNARY_MINUS
            label = '-';
        elseif type==ELEM_POWER
            label = '.^';
        elseif type==ELEM_MULT
            label = '.*';
        elseif type==ELEM_DIV
            label = './';
        elseif type==ELEM_BACKDIV
            label = '.\\\\';
        elseif type==RANGE
            label = 'RANGE';
        elseif type==STEPPED_RANGE
            label = 'STEPPED\\nRANGE';
        elseif type==GREATER
            label = '>';
        elseif type==GREATER_EQUAL
            label = '>=';
        elseif type==LESS
            label = '<';
        elseif type==LESS_EQUAL
            label = '<=';
        elseif type==EQUALITY
            label = '==';
        elseif type==NOT_EQUAL
            label = '~=';
        elseif type==AND
            label = '&';
        elseif type==SHORT_AND
            label = '&&';
        elseif type==OR
            label = '|';
        elseif type==SHORT_OR
            label = '||';
        elseif type==CALL
            label = 'CALL';
        elseif type==COLON
            label = ':';
        elseif type==ARG_LIST
            label = 'ARGS';
        elseif type==END
            label = 'end';
        elseif type==CALL_STMT
            label = ['CALL_STMT\\nverbosity=',num2str(nodes(VERBOSITY,node))];
        elseif type==EXPR_STMT
            label = ['EXPR_STMT\\nverbosity=',num2str(nodes(VERBOSITY,node))];
        elseif type==VERTICAT
            label = 'VERTICAT';
        elseif type==HORIZCAT
            label = 'HORIZCAT';
        elseif type==EMPTYMAT
            label = 'EMPTYMAT';
        elseif type==UNARYCELL
            label = 'UNARYCELL';
        elseif type==VERTICELL
            label = 'VERTICELL';
        elseif type==HORIZCELL
            label = 'HORIZCELL';
        elseif type==EMPTYCELL
            label = 'EMPTYCELL';
        elseif type==IGNORED_OUTPUT
            label = 'IGNORED\\nOUTPUT';
        elseif type==IF
            label = 'IF';
        elseif type==ELSEIF
            label = 'ELSEIF';
        elseif type==ELSE
            label = 'ELSE';
        elseif type==FOR
            label = 'FOR';
        elseif type==PARFOR
            label = 'PARFOR';
        elseif type==WHILE
            label = 'WHILE';
        elseif type==TRY
            label = 'TRY';
        elseif type==CATCH
            label = 'CATCH';
        elseif type==GLOBAL
            label = 'GLOBAL';
        elseif type==PERSISTENT
            label = 'PERSISTENT';
        elseif type==SPMD
            label = 'SPMD';
        elseif type==RETURN
            label = 'RETURN';
        elseif type==BREAK
            label = 'BREAK';
        elseif type==CONTINUE
            label = 'CONTINUE';
        elseif type==SWITCH
            label = 'SWITCH';
        elseif type==CASE
            label = 'CASE';
        elseif type==OTHERWISE
            label = 'OTHERWISE';
        elseif type==DOT
            label = 'MEMBER';
        elseif type==CELL_CALL
            label = 'CELL\\nCALL';
        elseif type==META_CLASS
            label = 'META_CLASS';
        elseif type==LAMBDA
            label = '@';
        elseif type==FUNCTION_LAMBDA
            label = '@';
        elseif type==FUN_REF
            label = ['FUN_REF to ', num2str(nodes(REF,node))];
        elseif type==VAR_REF
            label = ['VAR_REF to ', num2str(nodes(REF,node))];
        elseif type==FUN_CALL
            label = 'FUN_CALL';
        elseif type==MATRIX_ACCESS
            label = 'MAT_ACCESS';
        elseif type==OUT_ARG_LIST
            label = 'OUT_ARGS';
        else
            label = 'No labeling rule';
        end
    end

    traverse(root,NONE,@dotter,@NO_POSTORDER);
    fprintf(dot_file,'}');
    fclose(dot_file);
    
    %%
    % If you do not have a .dot viewer installed, you can view the
    % resulting graph online using a site such as
    % <http://www.webgraphviz.com/ web graph viz>.
    
    %% Symbol Table Resolution
    % This is a difficult stage since C++ has fundamentally different
    % scoping rules from MATLAB. In MATLAB, scopes are primary defined by
    % functions, and we are allowed to nest functions. In C++, nesting
    % functions is not supported. Fortunately, C++17 introduced lambda
    % functions, which behave similarly to MATLAB functions when used with
    % automatic capture (which is actually frowned upon, but we mostly care
    % about copying MATLAB's semantics).
    %
    % DO THIS: need to account for lambdas
    %
    % Consider the following example:
    
    %{
        function helloWorld()
            function setString()
                hello_world = "Hello World!";
            end
            
            setString();
            disp(hello_world)
        end
    %}
    
    %%
    % We would convert this to C++ by:
    
    %{
        #include <iostream>
        #include <string>
        #include <functional>

        std::function<void(void)> helloWorld = [&](){
            std::string hello_world;

            std::function<void(void)> setString = [&](){
                    hello_world = "Hello World!";
            };

            setString();
            std::cout << hello_world;
        };
    %}
    
    %%
    % So the challenge is making sure variables are declared at the right
    % scope and at the right time, i.e. before they are used in any child
    % functions. If they are used first at the topmost level they occur,
    % then they could be declared and initialized simultaneously, which
    % would result in more readable code.
    %
    % The first step forward to recognizing where identifiers are declared
    % is to build a symbol table
    % data structure with MATLAB's scoping rules.
    % We will implement this data structure as a tree of the function
    % scopes, where each node in the tree
    % includes a linked list of identifiers. These elements are stored in
    % the highest scope in which they are used. Consider the following
    % MATLAB code:
    
    %{
        a = 2;
        global b
        b = 3;
        e = 4;
        function outer()
            a = 1;
            function fun1()
                global b
                b = 1;
                c = 1;
                function funA()
                    c = 3;
                end
                funA();
            end
            function fun2()
                c = 2;
                function funA()
                    a = 2;
                    c = 4;
                end
                funA();
            end
            global e
            e = 2;
        end
    %}
    
    %%
    % The symbol table would look like this:
    
    %%
    %
    % <<./Fig/SymbolTableExample.svg>>
    %
    
    %%
    % The linked-list is sorted
    % in the order of occurence from top to bottom of the code, since this
    % will map well to C++ and let us know when we need to declare
    % variables without initializers.
    %
    % The tree portion of the symbol table is straightforward to build by
    % searching the parse tree. For the linked lists, we perform a
    % pre-order traversal of the scope tree and resolve each identifier. If
    % an identifier is not present at higher levels, we add it at the level
    % we are searching. By searching from top to bottom, we are able to
    % respect MATLAB's scoping rules. We only search up the tree when
    % resolving identifiers, because parallel scopes do not have access to
    % each other (see [3] for more information).
    %
    % Note that unlike C++, variables defined at the top level are not
    % visible within functions. MATLAB uses a seperate keyword 'global' to
    % share variables globally [?]. This is simple to implement in C++; if
    % a variable is global, we don't redeclare it in nested scopes, and if
    % it isn't global, we do shadow it. MATLAB also uses a keyword
    % 'persistent' which allows a variable to retain its value between
    % function calls [?]. Global variables already maintain state between
    % MEX calls, but the 'persistent' keyword is still tricky since it is
    % normally accompanied by an 'if isempty(-VAR-)' initializer in MATLAB.
    % This pattern is a little complicated to recognize, and we would also
    % need to implement a system to resolve name collisions if we simply
    % moved persistent variables to the global scope in C++, so we will
    % disallow persistent variables for now.
    %
    % Since we may later want to optimize the implementation of the symbol
    % table, we use some general methods:
    
    function addScope(scope_node,parent)
        if parent~=root
            nodes(SYMBOL_TREE_PARENT,scope_node) = parent;
        end
        if parent~=NONE
            resolveFunction(scope_node,parent);
        end
    end

    function id = getParentScope(scope_node)
        id = nodes(SYMBOL_TREE_PARENT,scope_node);
    end

    function resolveFunction(node,parent)
        list_elem = nodes(FIRST_SYMBOL,parent);
        if list_elem==NONE
            nodes(FIRST_SYMBOL,PARENT) = node;
            return
        end
        
        name = readTextNode(nodes(FUN_NAME,node));
        
        prev = list_elem;
        while list_elem~=NONE
            elem_name = readTextNode(nodes(FUN_NAME,list_elem));
            if strcmp(name,elem_name)
                error(char(strcat("Function '", name, ...
                    "' was redefined on line ", num2str(nodes(LINE,nodes(FUN_NAME,node))), ...
                    ", previously defined on line ", ...
                    num2str(nodes(LINE,nodes(FUN_NAME,list_elem))), ".")));
            end
            
            prev = list_elem;
            list_elem = nodes(SYMBOL_LIST_LINK,list_elem);
        end
        
        nodes(SYMBOL_LIST_LINK,prev) = node;
    end
    
    %%
    % In our first pass, we build the tree structure of the symbol table.
    % We use a global variable to indicate the current parent scope.
    
    PARENT = root;
    SYMBOL_TREE_PARENT = 11;
    SYMBOL_LIST_LINK = 12;
    FIRST_SYMBOL = 13;
    
    %%
    % We have a pre-order function to add any function nodes as new scopes,
    % then set the global parent node to this function node before visiting
    % the children.
    %
    % We will also start building the linked lists with function names.
    % Ideally we would try to preserve the order of the functions in the
    % linked-list, and only swap elements when a function is called before
    % it is defined. This would make the code more readable (at least as
    % much as we trust the original author), but for a first pass it is too
    % heavy of a burden.
    
    function descend = scopeBuildingVisitor(node,parent)
        descend = true;
        if nodes(NODE_TYPE,node) == FUNCTION
            addScope(node,PARENT);
            PARENT = node;
        end
    end

    %%
    % Now we need a post-order function to reset the global parent variable
    % to the node's parent before moving back up the tree.
    
    function resetParent(node,parent)
        if nodes(NODE_TYPE,node) == FUNCTION
            PARENT = getParentScope(node);
            if PARENT==NONE
                PARENT = root;
            end
        end
    end

    %%
    % Finally we can resolve the nested function structure:
    
    traverse(root,NONE,@scopeBuildingVisitor,@resetParent);
    
    %%
    % Let's generate a DOT file to make sure we're handling this correctly.
    
    dot_name = [extensionless_name, '_scopes.dot'];
    dot_file = fopen(dot_name,'w');
    fprintf(dot_file,'digraph {\r\n\trankdir=BT\r\n\r\n');
    
    fprintf(dot_file,'\t');
    fprintf(dot_file,'base [label="Base\\nWorkspace",color="gold"]\r\n');
    
    if num_global > 0
        fprintf(dot_file,'\t');
        fprintf(dot_file,'globals [label="Globals",color="purple"]\r\n');
    end
    
    function descend = scopeDotter(node,parent)
        descend = true;
        if nodes(NODE_TYPE,node)==FUNCTION
            fprintf(dot_file,'\t');
            fprintf(dot_file,['node_', num2str(node), ' [label="']);
            name = nodes(FUN_NAME,node);
            fprintf(dot_file,getLabel(name));
            fprintf(dot_file,'",color="brown"]\r\n');
            parent = nodes(SYMBOL_TREE_PARENT,node);
            if parent~=NONE
                fprintf(dot_file,['\tnode_', num2str(node), ...
                    ' -> node_', num2str(parent), ' [color="brown"]\r\n\r\n']);
            end
            
            input_block = nodes(FUN_INPUT,node);
            input = nodes(FIRST_PARAMETER, input_block);
            if input~=NONE
                %Create a cluster for inputs
                fprintf(dot_file,['\tsubgraph cluster_',num2str(input_block),' {\r\n']);
                fprintf(dot_file,'\t\trank=same;\r\n');
                fprintf(dot_file,'\t\tlabel="Input";\r\n');
                
                first_name = ['input_',num2str(input_block),'_',num2str(input)];
                fprintf(dot_file,['\t\t', first_name, ' [label="']);
                if nodes(NODE_TYPE,input)==FUNCTION
                    name = getLabel(nodes(FUN_NAME,input));
                elseif nodes(NODE_TYPE,input)==IDENTIFIER
                    name = getLabel(input);
                end
                fprintf(dot_file,name);
                fprintf(dot_file,'",color="blue"]\r\n');
                
                prev_name = first_name;
                input = nodes(LIST_LINK,input);
            
                while input ~= NONE
                    fprintf(dot_file,'\t\t');
                    curr_name = ['input_',num2str(input_block),'_',num2str(input)];
                    fprintf(dot_file,[curr_name, ' [label="']);
                    if nodes(NODE_TYPE,input)==FUNCTION
                        name = getLabel(nodes(FUN_NAME,input));
                    elseif nodes(NODE_TYPE,input)==IDENTIFIER
                        name = getLabel(input);
                    end
                    fprintf(dot_file,name);
                    fprintf(dot_file,'",color="blue"]\r\n');
                    fprintf(dot_file,['\t\t', prev_name, ...
                        ' -> ', curr_name, ' [color="blue",constraint=false]\r\n\r\n']);

                    prev_name = curr_name;
                    input = nodes(LIST_LINK,input);
                end
                fprintf(dot_file,'\t}\r\n');
                fprintf(dot_file,['\tnode_', num2str(node), ' -> ', ...
                    first_name,'[constraint=false]\r\n\r\n']);
            end
            
            output_block = nodes(FUN_OUTPUT,node);
            output = nodes(FIRST_PARAMETER, output_block);
            if output~=NONE
                %Create a cluster for inputs
                fprintf(dot_file,['\tsubgraph cluster_',num2str(output_block),' {\r\n']);
                fprintf(dot_file,'\t\trank=same;\r\n');
                fprintf(dot_file,'\t\tlabel="Output";\r\n');
                
                first_name = ['output_',num2str(output_block),'_',num2str(output)];
                fprintf(dot_file,['\t\t', first_name, ' [label="']);
                if nodes(NODE_TYPE,output)==FUNCTION
                    name = getLabel(nodes(FUN_NAME,output));
                elseif nodes(NODE_TYPE,output)==IDENTIFIER
                    name = getLabel(output);
                end
                fprintf(dot_file,name);
                fprintf(dot_file,'",color="red"]\r\n');
                
                prev_name = first_name;
                output = nodes(LIST_LINK,output);
            
                while output ~= NONE
                    fprintf(dot_file,'\t\t');
                    curr_name = ['output_',num2str(input_block),'_',num2str(output)];
                    fprintf(dot_file,[curr_name, ' [label="']);
                    if nodes(NODE_TYPE,output)==FUNCTION
                        name = getLabel(nodes(FUN_NAME,output));
                    elseif nodes(NODE_TYPE,output)==IDENTIFIER
                        name = getLabel(output);
                    end
                    fprintf(dot_file,name);
                    fprintf(dot_file,'",color="red"]\r\n');
                    fprintf(dot_file,['\t\t', prev_name, ...
                        ' -> ', curr_name, ' [color="red",constraint=false]\r\n\r\n']);

                    prev_name = curr_name;
                    output = nodes(LIST_LINK,output);
                end
                fprintf(dot_file,'\t}\r\n');
                fprintf(dot_file,['\tnode_', num2str(node), ' -> ', ...
                    first_name,'[constraint=false]\r\n\r\n']);
            end
        end
    end

    traverse(root,NONE,@scopeDotter,@NO_POSTORDER);
    fprintf(dot_file,'}');
    fclose(dot_file);
    
    %%
    % Great, so now each scope has a link to its parent. Now we need to
    % actually resolve identifiers. Since C++ requires a variable to be
    % declared in the outermost scope it is used, a pre-order search will
    % be appropriate. We declare another global variable for the active
    % scope, which we will update during the traversal.
    
    PARENT = root;
    
    function descend = resolvingVisitor(node,parent)
        descend = true;
        type = nodes(NODE_TYPE,node);
        
        if type==FUNCTION
            PARENT = node; %already resolved
        elseif type==IDENTIFIER
            if parent~=PARENT %Hack to compensate for functions having IDENTIFIER names
                resolveIdentifier(node,PARENT);
            end
        elseif type==INPUT_LIST
            elem = nodes(FIRST_PARAMETER,node);
            while elem~=NONE
                resolveInputParameter(elem);
                elem = nodes(LIST_LINK,elem);
            end
            descend = false;
        elseif type==OUTPUT_LIST
            elem = nodes(FIRST_PARAMETER,node);
            while elem~=NONE
                resolveOutputParameter(elem,PARENT);
                elem = nodes(LIST_LINK,elem);
            end
            descend = false;
        elseif type==GLOBAL
            resolveGlobal(node,PARENT);
        elseif type==PERSISTENT
            error(char(strcat("Translator does not support persistent variables. (Symbol Table)")));
        end
    end

    function resolveInputParameter(node)
        name = readTextNode(node);
        if strcmp(name,"varargin")
            error(char(strcat("Translator does not support 'varargin'. (Symbol Table)")));
        end

        next = nodes(LIST_LINK,node);
        while next~=NONE
            next_name = readTextNode(next);
            if strcmp(name,next_name)
                error(char(strcat("The variable ",name," was mentioned more than once as an input.")));
            end

            next = nodes(LIST_LINK,next);
        end
    end

    function resolveOutputParameter(node,scope)
        name = readTextNode(node);

        next = nodes(LIST_LINK,node);
        while next~=NONE
            next_name = readTextNode(next);
            if strcmp(name,next_name)
                error(char(strcat("The variable ",name," was mentioned more than once as an output.")));
            end

            next = nodes(LIST_LINK,next);
        end
        
        %Allow an input to be re-used as an output
        list_elem = nodes(FIRST_PARAMETER, nodes(FUN_INPUT,scope));
        while list_elem~=NONE
            elem_name = readTextNode(list_elem);
            if strcmp(name,elem_name)
                nodes(NODE_TYPE,node) = VAR_REF;
                nodes(REF,node) = list_elem;
                return;
            end

            list_elem = nodes(LIST_LINK,list_elem);
        end
    end

    function resolveIdentifier(node,parent)
        if findCanonicalReference(node,PARENT) == NONE
            list_elem = nodes(FIRST_SYMBOL,PARENT);
            if list_elem==NONE
                nodes(FIRST_SYMBOL,PARENT) = node;
                return
            end

            while nodes(SYMBOL_LIST_LINK,list_elem)~=NONE
                list_elem = nodes(SYMBOL_LIST_LINK,list_elem);
            end

            nodes(SYMBOL_LIST_LINK,list_elem) = node;
        end
    end

    function id = findCanonicalReference(node,scope)
        name = readTextNode(node);
        while scope~=NONE
            if ~is_script || scope~=root
                list_elem = nodes(FIRST_PARAMETER, nodes(FUN_INPUT,scope));
                while list_elem~=NONE
                    elem_name = readTextNode(list_elem);
                    if strcmp(name,elem_name)
                        nodes(NODE_TYPE,node) = VAR_REF;
                        nodes(REF,node) = list_elem;
                        id = list_elem;
                        return;
                    end
                    
                    list_elem = nodes(LIST_LINK,list_elem);
                end
                
                list_elem = nodes(FIRST_PARAMETER, nodes(FUN_OUTPUT,scope));
                while list_elem~=NONE
                    elem_name = readTextNode(list_elem);
                    if strcmp(name,elem_name)
                        nodes(NODE_TYPE,node) = VAR_REF;
                        nodes(REF,node) = list_elem;
                        id = list_elem;
                        return;
                    end
                    
                    list_elem = nodes(LIST_LINK,list_elem);
                end
            end
            
            list_elem = nodes(FIRST_SYMBOL,scope);
            while list_elem~=NONE
                if nodes(NODE_TYPE,list_elem)==IDENTIFIER
                    elem_name = readTextNode(list_elem);
                    if strcmp(name,elem_name)
                        nodes(NODE_TYPE,node) = VAR_REF;
                        nodes(REF,node) = list_elem;
                        id = list_elem;
                        return;
                    end
                elseif nodes(NODE_TYPE,list_elem)==FUNCTION
                    elem_name = readTextNode(nodes(FUN_NAME,list_elem));
                    if strcmp(name,elem_name)
                        nodes(NODE_TYPE,node) = FUN_REF;
                        nodes(REF,node) = list_elem;
                        nodes(DATA_TYPE,node) = NA;
                        id = list_elem;
                        return;
                    end
                end
                
                list_elem = nodes(SYMBOL_LIST_LINK,list_elem);
            end
            
            scope = nodes(SYMBOL_TREE_PARENT,scope);
        end
        
        %We've exhausted the possibilities for a variable reference, but it
        %may be a function from the base workspace.
        id = searchBaseWorkspaceForFunctions(node);
    end

    function id = searchBaseWorkspaceForFunctions(node)
        name = readTextNode(node);

        list_elem = nodes(FIRST_SYMBOL,root);
        while list_elem~=NONE
            if nodes(NODE_TYPE,list_elem)==FUNCTION
                elem_name = readTextNode(nodes(FUN_NAME,list_elem));
                if strcmp(name,elem_name)
                    nodes(NODE_TYPE,node) = FUN_REF;
                    nodes(REF,node) = list_elem;
                    nodes(DATA_TYPE,node) = NA;
                    id = list_elem;
                    return;
                end
            end

            list_elem = nodes(SYMBOL_LIST_LINK,list_elem);
        end
        
        id = NONE;
    end

    function resolveGlobal(node,parent)
        %if findGlobal(node) == NONE
            %DO THIS - have 'global_base' refering to first global node
        %end
        error(char(strcat("Translator does not support global variables. (Symbol Table)")));
    end

    traverse(root,NONE,@resolvingVisitor,@resetParent);

    %%
    % In the future it will be absolutely essential to include global
    % MATLAB functions such as 'true', 'false', 'pi', 'cos()', or even 'i'
    % and 'j'. We will want to recognize some of these functions and
    % provide C++ implementations. For less crucial functions, the
    % compiler could test any undefined identifiers using 'exist(id)', and
    % the C++/MEX code can invoke the MATLAB implementation so that we
    % wouldn't have to individually account for every function.
    % Since these identifiers are not reserved, they may be the target of
    % assignments. Some filthy nihilist can write 'true = false', and
    % MATLAB will not argue the point. The resolver needs to handle this as
    % well.
    %
    % For now we will assume that every identifier refers to an entity in
    % the local file. Of course this assumption is crippling, but it will
    % let us see the end of translator pipeline without fussing too much
    % over symbol resolution.
    %
    % In the parser we treated function calls and matrix accesses
    % uniformly. Now we have done the work to differentiate the two. We'll
    % traverse through the tree resolving any calls we see:
    
    function keep_going = resolveCall(node,parent)
        keep_going = true;
        if nodes(NODE_TYPE,node)==CALL
            lhs = nodes(LHS,node);
            if nodes(NODE_TYPE,lhs)==FUN_REF
                nodes(NODE_TYPE,node) = FUN_CALL;
                validateFunCallArgs(node);
                setUnusedFunCallsToCallStmts(node,parent);
            else
                nodes(NODE_TYPE,node) = MATRIX_ACCESS;
            end
        elseif nodes(NODE_TYPE,node)==FUNCTION
            PARENT = node;
        end
    end

    function validateFunCallArgs(node)
        args = nodes(RHS,node);
        input = nodes(FIRST_PARAMETER,args);
        traverse(args,NONE,@searchForEnd,@NO_POSTORDER)
        
        while input~=NONE
            if nodes(NODE_TYPE,input)==COLON || found_invalid_end
                error(['"',getName(nodes(LHS,node)),...
                    '" previously appeared to be used as a function ',...
                    'or command, conflicting with its use here as ',...
                    'the name of a variable.\n%s'],...
                    ['A possible cause of this error is that you ',...
                    'forgot to initialize the variable, or you have ',...
                    'initialized it implicitly using load or eval.'])
            end
            
            input = nodes(LIST_LINK,input);
        end
    end

    found_invalid_end = false;
    function keep_going = searchForEnd(node,name)
        keep_going = true;
        if nodes(NODE_TYPE,node)==END
            found_invalid_end = true;
        elseif nodes(NODE_TYPE,node)==MATRIX_ACCESS || nodes(NODE_TYPE,node)==CALL
            keep_going = false;
        end
    end

    function setUnusedFunCallsToCallStmts(node,parent)
        ref = nodes(LHS,node);
        fun = nodes(REF,ref);
        out_list = nodes(FUN_OUTPUT,fun);
        output = nodes(FIRST_PARAMETER,out_list);
        if nodes(NODE_TYPE,parent)==EXPR_STMT
            nodes(NODE_TYPE,parent) = CALL_STMT;
            nodes(LHS,parent) = node;
            nodes(RHS,parent) = nodes(RHS,node);
            nodes(DATA_TYPE,parent) = NA;
            nodes(6,parent) = ref;
            
            nodes(NODE_TYPE,node) = OUT_ARG_LIST;
            nodes(DATA_TYPE,node) = NA;
            nodes(FIRST_PARAMETER,node) = NONE;
        elseif output==NONE
        	error(['Error using ',getName(fun)],'Too many output arguments.')
        end
    end

    traverse(root,NONE,@resolveCall,@resetParent)
    
    %%
    % Great, now let's create another DOT generator to make sure we're
    % still on track.
    
    dot_name = [extensionless_name, '_symbols.dot'];
    dot_file = fopen(dot_name,'w');
    fprintf(dot_file,'digraph {\r\n\trankdir=BT\r\n\r\n');
    
    fprintf(dot_file,'\t');
    fprintf(dot_file,'base [label="Base\\nWorkspace",color="gold"]\r\n');
    
    if num_global > 0
        fprintf(dot_file,'\t');
        fprintf(dot_file,'globals [label="Globals",color="purple"]\r\n');
    end
    
    function descend = listDotter(node,parent)
        descend = true;
        if nodes(NODE_TYPE,node)==FUNCTION
            prev_name = ['node_', num2str(node)];
            list_elem = nodes(FIRST_SYMBOL,node);
            
            fprintf(dot_file,['\tsubgraph cluster_',num2str(node),' {\r\n']);
            fprintf(dot_file,'\t\trank=same;\r\n');
            fprintf(dot_file,'\t\tlabel="Local Workspace";\r\n');
            
            while list_elem ~= NONE
                fprintf(dot_file,'\t\t');
                curr_name = ['leaf_',num2str(node),'_',num2str(list_elem)];
                fprintf(dot_file,[curr_name, ' [label="']);
                if nodes(NODE_TYPE,list_elem)==FUNCTION
                    name = getLabel(nodes(FUN_NAME,list_elem));
                elseif nodes(NODE_TYPE,list_elem)==IDENTIFIER
                    name = getLabel(list_elem);
                end
                fprintf(dot_file,name);
                fprintf(dot_file,'",color="green"]\r\n');
                fprintf(dot_file,['\t\t', prev_name, ...
                    ' -> ', curr_name, ' [color="green",constraint=false]\r\n\r\n']);
                prev_name = curr_name;
                
                list_elem = nodes(SYMBOL_LIST_LINK,list_elem);
            end
            
            fprintf(dot_file,'\t}\r\n');
        elseif is_script && node==root
            prev_name = 'base';
            list_elem = nodes(FIRST_SYMBOL,node);
            
            fprintf(dot_file,['\tsubgraph cluster_',num2str(node),' {\r\n']);
            fprintf(dot_file,'\t\trank=same;\r\n'); %How to make this work?
            
            while list_elem ~= NONE
                fprintf(dot_file,'\t\t');
                curr_name = ['leaf_',num2str(node),'_',num2str(list_elem)];
                fprintf(dot_file,[curr_name, ' [label="']);
                if nodes(NODE_TYPE,list_elem)==FUNCTION
                    name = getLabel(nodes(FUN_NAME,list_elem));
                elseif nodes(NODE_TYPE,list_elem)==IDENTIFIER
                    name = getLabel(list_elem);
                end
                fprintf(dot_file,name);
                fprintf(dot_file,'",color="blue"]\r\n');
                fprintf(dot_file,['\t\t', prev_name, ...
                    ' -> ', curr_name, ' [color="blue",constraint=false]\r\n\r\n']);
                prev_name = curr_name;
                
                list_elem = nodes(SYMBOL_LIST_LINK,list_elem);
            end
            
            fprintf(dot_file,'\t}\r\n');
        end
    end

    traverse(root,NONE,@scopeDotter,@NO_POSTORDER);
    traverse(root,NONE,@listDotter,@NO_POSTORDER);
    fprintf(dot_file,'}');
    fclose(dot_file);
    
    %%
    % For code generation purposes, we also need to check if any call
    % statement has multiple output arguments without using all the output
    % parameters.
    
    function searchIncompleteMultiOutput(node,parent)
        if nodes(NODE_TYPE,node)==CALL_STMT
            num_outputs = 0;
            num_out_args = 0;
            
            out_arg = nodes(FIRST_PARAMETER,nodes(LHS,node));
            while out_arg~=NONE
                num_out_args = num_out_args + 1;
                out_arg = nodes(LIST_LINK,out_arg);
            end
            
            output = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,nodes(REF,nodes(6,node))));
            while output~=NONE
                num_outputs = num_outputs + 1;
                output = nodes(LIST_LINK,output);
            end
            
            if num_outputs < num_out_args
                error(['"',getName(nodes(LHS,node)),...
                    '" previously appeared to be used as a function ',...
                    'or command, conflicting with its use here as ',...
                    'the name of a variable.\n%s'],...
                    ['A possible cause of this error is that you ',...
                    'forgot to initialize the variable, or you have ',...
                    'initialized it implicitly using load or eval.'])
            elseif num_out_args < num_outputs && num_out_args > 1
                has_ignored_outputs = true;
            end
        end
    end

    traverse(root,NONE,@NO_PREORDER,@searchIncompleteMultiOutput)
    
    %%
    % It would also be helpful to disambiguate function identifiers from
    % normal identifiers, so we make a pass to do that.
    
    function disambiguateIdentifiers(node,parent)
        if nodes(NODE_TYPE,node)==FUNCTION
            nodes(NODE_TYPE,nodes(FUN_NAME,node)) = FUN_IDENTIFIER;
        end
    end

    traverse(root,NONE,@NO_PREORDER,@disambiguateIdentifiers)
    
    %% Size Resolution
    % Although we could very well resolve types and sizes together, both
    % solutions will involve a good bit of code, so we opt to seperate the
    % two problems.
    %
    % Size resolution is complicated by MATLAB's overloaded arithmatic
    % operators. Unlike mathematics in general, MATLAB defines addition of
    % a scalar and a matrix, e.g. [1,2;3,4] + 1 -> [2,3;4,5]. A similar
    % rule applies for adding vectors to matrices. Thus it is sometimes not
    % possible to use an operand with known size to deduce the size of
    % other operands. This leads to ambiguity in sizes. The following
    % simple function may accept a scalar, vector, or matrix:
    
    %{
        function result = add5(num)
            result = num + 5;
        end
    %}
    
    %%
    % Thus to faithfully capture this behavior in C++, we would have to
    % implement 'num' and 'result' as dynamically sized matrices. This is
    % rather crippling, particularly since the majority of additions  and
    % subtractions will not be matrix-scalar operations. For this reason we
    % defined the input flag 'uses_mathematically_correct_notation', by
    % which the user can assure us matrix addition requires both operands
    % are the same size.
    %
    % Some tricky programs may have sizes which are only statically
    % knowable by applying some level of symbolic computation. We will
    % avoid any approaches that sophisticated for now and only work with
    % concrete values.
    %
    % We define method for setting the number of rows or columns, which
    % will also have the side effect of letting us know a size has been
    % deduced for this pass over the tree.
    
    size_was_modified = true;
    
    function setRows(node,rows)
        nodes(ROWS,node) = rows;
        size_was_modified = true;
    end

    function setCols(node,rows)
        nodes(COLS,node) = rows;
        size_was_modified = true;
    end

    function copyRows(follower,leader)
        nodes(ROWS,follower) = nodes(ROWS,leader);
        size_was_modified = true;
    end

    function copyCols(follower,leader)
        nodes(COLS,follower) = nodes(COLS,leader);
        size_was_modified = true;
    end

    %%
    % A lot of the logic is common accross different node types, and we
    % want to seperate the logic from the visitor function, so we define
    % convencience functions here:
    
    function matchRows(node,other)
        %Eight column possiblities, seven of which are handled
        if nodes(ROWS,other)~=NONE && nodes(ROWS,node)~=NONE
            assert( nodes(ROWS,other)==nodes(ROWS,node), 'Size mismatch' );
        elseif nodes(ROWS,other)~=NONE
            copyRows(node,other);
        elseif nodes(ROWS,node)~=NONE
            copyRows(other,node);
        end
    end

    function matchCols(node,other)
        %Eight column possiblities, seven of which are handled
        if nodes(COLS,other)~=NONE && nodes(COLS,node)~=NONE
            assert( nodes(COLS,other)==nodes(COLS,node), 'Size mismatch' );
        elseif nodes(COLS,other)~=NONE
            copyCols(node,other);
        elseif nodes(COLS,node)~=NONE
            copyCols(other,node);
        end
    end
    
    function matchRows3(node,lhs,rhs)
        %Eight column possiblities, seven of which are handled
        if nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)~=NONE
            assert( nodes(ROWS,lhs)==nodes(ROWS,rhs), 'Vertical concatenation size mismatch' );
            assert( nodes(ROWS,lhs)==nodes(ROWS,node), 'Vertical concatenation size mismatch' );
        elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)==NONE
            assert( nodes(ROWS,lhs)==nodes(ROWS,rhs), 'Vertical concatenation size mismatch' );
            copyRows(node,lhs);
        elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)~=NONE
            assert( nodes(ROWS,lhs)==nodes(ROWS,node), 'Vertical concatenation size mismatch' );
            copyRows(rhs,lhs);
        elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)~=NONE
            assert( nodes(ROWS,rhs)==nodes(ROWS,node), 'Vertical concatenation size mismatch' );
            copyRows(lhs,rhs);
        elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)==NONE
            copyRows(rhs,lhs);
            copyRows(node,lhs);
        elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)==NONE
            copyRows(lhs,rhs);
            copyRows(node,rhs);
        elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)~=NONE
            copyRows(lhs,node);
            copyRows(rhs,node);
        end
    end

    function matchColumns3(node,lhs,rhs)
        %Eight column possiblities, seven of which are handled
        if nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)~=NONE
            assert( nodes(COLS,lhs)==nodes(COLS,rhs), 'Vertical concatenation size mismatch' );
            assert( nodes(COLS,lhs)==nodes(COLS,node), 'Vertical concatenation size mismatch' );
        elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)==NONE
            assert( nodes(COLS,lhs)==nodes(COLS,rhs), 'Vertical concatenation size mismatch' );
            copyCols(node,lhs);
        elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)~=NONE
            assert( nodes(COLS,lhs)==nodes(COLS,node), 'Vertical concatenation size mismatch' );
            copyCols(rhs,lhs);
        elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)~=NONE
            assert( nodes(COLS,rhs)==nodes(COLS,node), 'Vertical concatenation size mismatch' );
            copyCols(lhs,rhs);
        elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)==NONE
            copyCols(rhs,lhs);
            copyCols(node,lhs);
        elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)==NONE
            copyCols(lhs,rhs);
            copyCols(node,rhs);
        elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)~=NONE
            copyCols(lhs,node);
            copyCols(rhs,node);
        end
    end

    function softMatchRows3(node,lhs,rhs)
        %One operand may have a dimension of one and the other have greater
        %than one.
        if nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)~=NONE
            if (nodes(ROWS,lhs)~=1 && nodes(ROWS,rhs)~=1) || nodes(ROWS,node)==1
                assert( nodes(ROWS,lhs)==nodes(ROWS,rhs), 'Size mismatch' );
                assert( nodes(ROWS,lhs)==nodes(ROWS,node), 'Size mismatch' );
            else
                assert( nodes(ROWS,lhs)==nodes(ROWS,node) || nodes(ROWS,rhs)==nodes(ROWS,node), 'Size mismatch' );
            end
        elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)==NONE
            if nodes(ROWS,lhs)~=1 && nodes(ROWS,rhs)~=1
                assert( nodes(ROWS,lhs)==nodes(ROWS,rhs), 'Size mismatch' );
                copyRows(node,lhs);
            elseif nodes(ROWS,lhs)~=1
                copyRows(node,lhs);
            else
                copyRows(node,rhs);
            end
        elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)~=NONE
            if nodes(ROWS,node)==1
                assert( nodes(ROWS,lhs)==nodes(ROWS,node), 'Size mismatch' );
                copyRows(rhs,lhs);
            elseif nodes(ROWS,lhs)~=1
                assert( nodes(ROWS,lhs)==nodes(ROWS,node), 'Size mismatch' );
            else
                copyRows(rhs,node);
            end
        elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)~=NONE
            if nodes(ROWS,node)==1
                assert( nodes(ROWS,rhs)==nodes(ROWS,node), 'Size mismatch' );
                copyRows(lhs,rhs);
            elseif nodes(ROWS,rhs)~=1
                assert( nodes(ROWS,rhs)==nodes(ROWS,node), 'Size mismatch' );
            else
                copyRows(lhs,node);
            end
        elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)==NONE
            if nodes(ROWS,lhs)~=1
                copyRows(node,lhs);
            end
        elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)==NONE
            if nodes(ROWS,rhs)~=1
                copyRows(node,rhs);
            end
        elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)~=NONE
            if nodes(ROWS,node)==1
                copyRows(lhs,node);
                copyRows(rhs,node);
            end
        end
    end

    function softMatchColumns3(node,lhs,rhs)
        %One operand may have a dimension of one and the other have greater
        %than one.
        if nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)~=NONE
            if (nodes(COLS,lhs)~=1 && nodes(COLS,rhs)~=1) || nodes(COLS,node)==1
                assert( nodes(COLS,lhs)==nodes(COLS,rhs), 'Size mismatch' );
                assert( nodes(COLS,lhs)==nodes(COLS,node), 'Size mismatch' );
            else
                assert( nodes(COLS,lhs)==nodes(COLS,node) || nodes(COLS,rhs)==nodes(COLS,node), 'Size mismatch' );
            end
        elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)==NONE
            if nodes(COLS,lhs)~=1 && nodes(COLS,rhs)~=1
                assert( nodes(COLS,lhs)==nodes(COLS,rhs), 'Size mismatch' );
                copyCols(node,lhs);
            elseif nodes(COLS,lhs)~=1
                copyCols(node,lhs);
            else
                copyCols(node,rhs);
            end
        elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)~=NONE
            if nodes(COLS,node)==1
                assert( nodes(COLS,lhs)==nodes(COLS,node), 'Size mismatch' );
                copyCols(rhs,lhs);
            elseif nodes(COLS,lhs)~=1
                assert( nodes(COLS,lhs)==nodes(COLS,node), 'Size mismatch' );
            else
                copyCols(rhs,node);
            end
        elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)~=NONE
            if nodes(COLS,node)==1
                assert( nodes(COLS,rhs)==nodes(COLS,node), 'Size mismatch' );
                copyCols(lhs,rhs);
            elseif nodes(COLS,rhs)~=1
                assert( nodes(COLS,rhs)==nodes(COLS,node), 'Size mismatch' );
            else
                copyCols(lhs,node);
            end
        elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)==NONE
            if nodes(COLS,lhs)~=1
                copyCols(node,lhs);
            end
        elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)==NONE
            if nodes(COLS,rhs)~=1
                copyCols(node,rhs);
            end
        elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)~=NONE
            if nodes(COLS,node)==1
                copyCols(lhs,node);
                copyCols(rhs,node);
            end
        end
    end

    function matchSquare(node)
        if nodes(ROWS,node)~=NONE || nodes(COLS,node)~=NONE
            assert(nodes(ROWS,node)==nodes(COLS,node), 'Size mismatch.')
        elseif nodes(ROWS,node)~=NONE
            setCols(node,nodes(ROWS,node))
        elseif nodes(COLS,node)~=NONE
            setRows(node,nodes(COLS,node))
        end
    end

    function matchScalar(node)
        if nodes(ROWS,node)==NONE
            setRows(node,1)
        else
            assert(nodes(ROWS,node)==1, 'Size mismatch.')
        end
        
        if nodes(COLS,node)==NONE
            setCols(node,1)
        else
            assert(nodes(COLS,node)==1, 'Size mismatch.')
        end
    end

    function matchScalar3(node,lhs,rhs)
        if nodes(ROWS,node)==NONE
            setRows(node,1)
        else
            assert(nodes(ROWS,node)==1, 'Operands to the || and && operators must be convertible to logical scalar values.')
        end
        
        if nodes(COLS,node)==NONE
            setCols(node,1)
        else
            assert(nodes(COLS,node)==1, 'Operands to the || and && operators must be convertible to logical scalar values.')
        end
        
        if nodes(ROWS,lhs)==NONE
            setRows(lhs,1)
        else
            assert(nodes(ROWS,lhs)==1, 'Operands to the || and && operators must be convertible to logical scalar values.')
        end

        if nodes(COLS,lhs)==NONE
            setCols(lhs,1)
        else
            assert(nodes(COLS,lhs)==1, 'Operands to the || and && operators must be convertible to logical scalar values.')
        end
        
        if nodes(ROWS,rhs)==NONE
            setRows(rhs,1)
        else
            assert(nodes(ROWS,rhs)==1, 'Operands to the || and && operators must be convertible to logical scalar values.')
        end

        if nodes(COLS,rhs)==NONE
            setCols(rhs,1)
        else
            assert(nodes(COLS,rhs)==1, 'Operands to the || and && operators must be convertible to logical scalar values.')
        end
    end

    function matchEmpty(node)
        if nodes(ROWS,node)==NONE
            setRows(node,0)
        else
            assert(nodes(ROWS,node)==0, 'Size mismatch.')
        end
        
        if nodes(COLS,node)==NONE
            setCols(node,0)
        else
            assert(nodes(COLS,node)==0, 'Size mismatch.')
        end
    end

    function matchSize(node,child)
        if nodes(ROWS,node)~=NONE && nodes(ROWS,child)~=NONE
            assert(nodes(ROWS,node)==nodes(ROWS,child), 'Size mismatch.')
        elseif nodes(ROWS,node)~=NONE
            copyRows(child, node)
        elseif nodes(ROWS,child)~=NONE
            copyRows(node, child)
        end
        
        if nodes(COLS,node)~=NONE && nodes(COLS,child)~=NONE
            assert(nodes(COLS,node)==nodes(COLS,child), 'Size mismatch.')
        elseif nodes(COLS,node)~=NONE
            copyCols(child, node)
        elseif nodes(COLS,child)~=NONE
            copyCols(node, child)
        end
    end

    function flipSize(node,child)
        if nodes(ROWS,node)~=NONE && nodes(COLS,child)~=NONE
            assert(nodes(ROWS,node)==nodes(COLS,child), 'Size mismatch.')
        elseif nodes(ROWS,node)~=NONE
            setCols(child, nodes(ROWS,node))
        elseif nodes(COLS,child)~=NONE
            setRows(node, nodes(COLS,child))
        end
        
        if nodes(COLS,node)~=NONE && nodes(ROWS,child)~=NONE
            assert(nodes(COLS,node)==nodes(ROWS,child), 'Size mismatch.')
        elseif nodes(COLS,node)~=NONE
            setRows(child, nodes(COLS,node))
        elseif nodes(ROWS,child)~=NONE
            setCols(node, nodes(ROWS,child))
        end
    end

    function matchColsToRows(left,right)
        if nodes(COLS,left)~=NONE && nodes(ROWS,right)~=NONE
            assert(nodes(COLS,left)==nodes(ROWS,right), 'Size mismatch.')
        elseif nodes(COLS,left)~=NONE
            setRows(right, nodes(COLS,left))
        elseif nodes(ROWS,right)~=NONE
            setCols(left, nodes(ROWS,right))
        end
    end
    
    %%
    % Now we finally create the visitor which will deduce and enforce sizes
    % for each expression node type.

    function descend = deduceSizes(node,parent)
        descend = true;
        type = nodes(NODE_TYPE,node);
        
        if type==IDENTIFIER
            %DO THIS
        elseif type==TRANSPOSE || type==COMP_CONJ
            child = nodes(UNARY_CHILD,node);
            flipSize(node,child);
        elseif type==GROUPING || type==NOT || type==UNARY_MINUS
            child = nodes(UNARY_CHILD,node);
            matchSize(node,child);
        elseif type==ELEM_MULT || type==ELEM_POWER || type==ELEM_DIV ||...
                type==ELEM_BACKDIV || type==GREATER || ...
                type==GREATER_EQUAL || type==LESS || type==LESS_EQUAL ||...
                type==EQUALITY || type==NOT_EQUAL || type==AND || type==OR
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            softMatchRows3(node,lhs,rhs)
            softMatchColumns3(node,lhs,rhs)
        elseif type==RANGE
            %DO THIS - tricky rules
        elseif type==STEPPED_RANGE
            %DO THIS - tricky rules
        elseif type==SHORT_AND || type==SHORT_OR
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            matchScalar3(node,lhs,rhs)
        elseif type==CALL
            %DO THIS
        elseif type==COLON
            %DO THIS
        elseif type==ARG_LIST
            %DO THIS
        elseif type==END
            matchScalar(node)
        elseif type==CALL_STMT
            %DO THIS
        elseif type==EXPR_STMT
            %DO THIS
        elseif type==VERTICAT || type==VERTICELL
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            matchColumns3(node,lhs,rhs);
            
            %Parent node has sum of child rows
            if nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)~=NONE
                assert( nodes(ROWS,node) == nodes(ROWS,lhs) + nodes(ROWS,rhs), 'Size error');
            elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)==NONE
                setRows(node, nodes(ROWS,lhs) + nodes(ROWS,rhs));
            elseif nodes(ROWS,lhs)~=NONE && nodes(ROWS,rhs)==NONE && nodes(ROWS,node)~=NONE
                setRows(rhs, nodes(ROWS,node) - nodes(ROWS,lhs));
            elseif nodes(ROWS,lhs)==NONE && nodes(ROWS,rhs)~=NONE && nodes(ROWS,node)~=NONE
                setRows(lhs, nodes(ROWS,node) - nodes(ROWS,rhs));
            end
            
        elseif type==HORIZCAT || type==HORIZCELL
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            matchRows3(node,lhs,rhs)
            
            %Parent node has sum of child cols
            if nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)~=NONE
                assert( nodes(COLS,node) == nodes(COLS,lhs) + nodes(COLS,rhs), 'Size error');
            elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)==NONE
                setCols(node, nodes(COLS,lhs) + nodes(COLS,rhs));
            elseif nodes(COLS,lhs)~=NONE && nodes(COLS,rhs)==NONE && nodes(COLS,node)~=NONE
                setCols(rhs, nodes(COLS,node) - nodes(COLS,lhs));
            elseif nodes(COLS,lhs)==NONE && nodes(COLS,rhs)~=NONE && nodes(COLS,node)~=NONE
                setCols(lhs, nodes(COLS,node) - nodes(COLS,rhs));
            end
            
        elseif type==EMPTYMAT || type==EMPTYCELL || type==IGNORED_OUTPUT
            matchEmpty(node)
        elseif type==UNARYCELL
            matchScalar(node)
        elseif type==IF
            %DO THIS - do statements add information?
        elseif type==ELSEIF
            %DO THIS
        elseif type==ELSE
            %DO THIS
        elseif type==FOR || type==PARFOR
            descend = false;
            
            assignment = nodes(LHS,node);
            iterator = nodes(LHS,assignment);
            matchScalar(iterator)
        elseif type==WHILE
            %DO THIS
        elseif type==TRY
            %DO THIS
        elseif type==CATCH
            %DO THIS
        elseif type==GLOBAL
            %DO THIS
        elseif type==PERSISTENT
            %DO THIS
        elseif type==SPMD
            %DO THIS
        elseif type==BREAK
            %DO THIS
        elseif type==CONTINUE
            %DO THIS
        elseif type==SWITCH
            %DO THIS
        elseif type==CASE
            %DO THIS
        elseif type==OTHERWISE
            %DO THIS
        elseif type==DOT
            %DO THIS
        elseif type==CELL_CALL
            %DO THIS
        elseif type==META_CLASS
            %DO THIS
        elseif type==LAMBDA
            %DO THIS
        elseif type==FUNCTION_LAMBDA
            %DO THIS
        elseif type==FUN_REF
            %DO THIS
        elseif type==VAR_REF
            if resizing_disallowed
                source = nodes(REF,node);
                matchSize(source,node)
            else
                error('Translator does not support dynamic resizing. (Size Resolution)')
            end
        elseif type==ADD || type==SUBTRACT
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            if uses_mathematically_correct_notation
                matchRows3(node,lhs,rhs)
                matchColumns3(node,lhs,rhs)
            else
                softMatchRows3(node,lhs,rhs)
                softMatchColumns3(node,lhs,rhs)
            end
        elseif type==MULTIPLY
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            matchColsToRows(lhs,rhs);
            matchRows(lhs,node);
            matchCols(rhs,node);
        elseif type==DIVIDE
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            %This allows psuedo-inverse
            matchCols(lhs,rhs);
            matchRows(lhs,node);
            matchColsToRows(node,rhs);
        elseif type==BACK_DIVIDE
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            %This allows psuedo-inverse
            matchRows(lhs,rhs);
            matchCols(rhs,node);
            matchColsToRows(lhs,node);
        elseif type==POWER
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            matchSquare(node);
            matchSquare(lhs);
            matchSquare(rhs);
            
            node_is_scalar = nodes(COLS,node)~=NONE && nodes(COLS,node) == 1;
            lhs_is_scalar = nodes(COLS,lhs)~=NONE && nodes(COLS,lhs) == 1;
            rhs_is_scalar = nodes(COLS,rhs)~=NONE && nodes(COLS,rhs) == 1;
            
            if ~lhs_is_scalar
                %? = matrix^?  -->  matrix = matrix^scalar
                matchScalar(rhs);
                matchSize(lhs,node);
            elseif ~rhs_is_scalar
                %? = ?^matrix  -->  matrix = scalar^matrix
                matchScalar(lhs);
                matchSize(rhs,node);
            elseif node_is_scalar
                %scalar = ?^?  -->  scalar = scalar^scalar
                matchScalar(lhs);
                matchScalar(rhs);
            elseif lhs_is_scalar && rhs_is_scalar
                %? = scalar^scalar  -->  scalar = scalar^scalar
                matchScalar(node);
            elseif ~node_is_scalar && lhs_is_scalar
                %matrix = scalar^?  --> matrix = scalar^matrix
                matchSize(node,rhs);
            elseif ~node_is_scalar && rhs_is_scalar
                %matrix = ?^scalar  --> matrix = matrix^scalar
                matchSize(node,lhs);
            end
            %Cannot deduce:
            % matrix = ?^?
            % ? = scalar^?
            % ? = ?^scalar
        elseif type==EQUALS
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            matchSize(lhs,rhs);
        end
    end


    %%
    % Now we write the driver that starts the size deduction:
    
    while size_was_modified
        size_was_modified = false;
        traverse(root,NONE,@deduceSizes,@deduceSizes);
    end
           
    %% Type Resolution
    % It is important to deduce the types of the parse tree nodes since C++
    % is statically typed. We can have different cases to handle types
    % dynamically, but that defeats the point of translating, so we should
    % only do so when absolutely necessary.
    %
    % In MATLAB, a variable may be assigned a new type. If we were very
    % sophisticated we could attempt to recognize this and create a
    % separate variable in C++, but for now we will throw an error when we
    % detect type mismatches.
    %
    % We will create matrices for each operation to show what type the
    % result will be based on the two operands. For instance, the following
    % matrix describes the resultant type of a subtraction based on the
    % left-hand-side and right-hand-size types:
    
    sub_result = NaN*ones(NUM_TYPES);
    sub_result(BOOLEAN,BOOLEAN) = INTEGER;
    sub_result(INTEGER,INTEGER) = INTEGER;
    sub_result(CHAR,CHAR) = INTEGER;
    sub_result(REAL,REAL) = REAL;
    sub_result(BOOLEAN,INTEGER) = INTEGER;
    sub_result(INTEGER,BOOLEAN) = sub_result(BOOLEAN,INTEGER);
    sub_result(BOOLEAN,CHAR) = INTEGER;
    sub_result(CHAR,BOOLEAN) = sub_result(BOOLEAN,CHAR);
    sub_result(BOOLEAN,REAL) = REAL;
    sub_result(REAL,BOOLEAN) = sub_result(BOOLEAN,REAL);
    sub_result(CHAR,INTEGER) = INTEGER;
    sub_result(INTEGER,CHAR) = sub_result(CHAR,INTEGER);
    sub_result(CHAR,REAL) = REAL;
    sub_result(REAL,CHAR) = sub_result(CHAR,REAL);
    sub_result(INTEGER,REAL) = REAL;
    sub_result(REAL,INTEGER) = sub_result(INTEGER,REAL);
    sub_result(STRING,:) = NA;
    sub_result(:,STRING) = NA;
    sub_result(CELL,:) = NA;
    sub_result(:,CELL) = NA;
    
    %%
    % We also want to define a matrix for when the result type and one of
    % the operands is known. We will use 'NA' to indicate an invalid
    % combination, and 'NONE' to indicate an ambigous combination. The rows
    % correspond to the result type, and the columns to the operand.
    
    sub_op = NaN*ones(NUM_TYPES);
    sub_op(BOOLEAN,:) = NA;
    sub_op(CHAR,:) = NA;
    sub_op(INTEGER,:) = NA;
    sub_op(INTEGER,INTEGER) = NONE;
    sub_op(INTEGER,CHAR) = NONE;
    sub_op(INTEGER,BOOLEAN) = NONE;
    sub_op(REAL,:) = NA;
    sub_op(REAL,CHAR) = REAL;
    sub_op(REAL,INTEGER) = REAL;
    sub_op(REAL,BOOLEAN) = REAL;
    sub_op(REAL,REAL) = NONE;
    sub_op(STRING,:) = NA;
    sub_op(CELL,:) = NA;
    
    %%
    % Finally, we want to declare a vector for when a single operand is
    % known:
    sub_single = NaN*ones(NUM_TYPES,1);
    sub_single(BOOLEAN) = NONE;
    sub_single(CHAR) = NONE;
    sub_single(INTEGER) = NONE;
    sub_single(REAL) = REAL;
    sub_single(STRING) = NA;
    sub_single(CELL) = NA;
    
    %%
    % In addition to deducing the types, we also want to note what the
    % child will be cast to in an operation, and if it is an implicit cast
    % in C++
    sub_cast = NaN*ones(NUM_TYPES,2);
    sub_cast(BOOLEAN,:) = [NA NA];
    sub_cast(CHAR,:) = [NA NA];
    sub_cast(INTEGER,:) = [INTEGER true];
    sub_cast(REAL,:) = [REAL true];
    sub_cast(STRING,:) = [NA NA];
    sub_cast(CELL,:) = [NA NA];
    
    %%
    % The subtraction matrix also applies for multiplication and powers.
    %
    % Division is a bit more interesting since it is not symmetric. We also
    % get into trouble here because MATLAB does not generally differentiate
    % integers from real numbers. Unlike C++, '1/2' evaluates to '0.5'.
    % However, division may also be used where an integer is required, e.g.
    % 'eye(6/3)' is valid.
    
    %DO THIS
    
    %%
    % Addition is problematic since the '+' operator may be used for string
    % concatenation, and as long as one operand is a string the other is
    % cast to a string. Thus the function
    
    %{
        function result = add110(num)
            result = num + 110;
        end
    %}
    %%
    % may be run with 'add110(2.5)' to produce the number '112.5', or may be
    % run as 'add110("he") + " world"' to produce the string "he110 world".
    % Not being able to statically determine whether the inputs and outputs
    % are numbers or strings is a challenge. DO THIS
    
    add_result = NaN*ones(NUM_TYPES);
    add_result(BOOLEAN,BOOLEAN) = INTEGER;
    add_result(INTEGER,INTEGER) = INTEGER;
    add_result(CHAR,CHAR) = INTEGER;
    add_result(REAL,REAL) = REAL;
    add_result(STRING,STRING) = STRING;
    add_result(BOOLEAN,INTEGER) = INTEGER;
    add_result(INTEGER,BOOLEAN) = add_result(BOOLEAN,INTEGER);
    add_result(BOOLEAN,CHAR) = INTEGER;
    add_result(CHAR,BOOLEAN) = add_result(BOOLEAN,CHAR);
    add_result(BOOLEAN,REAL) = REAL;
    add_result(REAL,BOOLEAN) = add_result(BOOLEAN,REAL);
    add_result(CHAR,INTEGER) = INTEGER;
    add_result(INTEGER,CHAR) = add_result(CHAR,INTEGER);
    add_result(CHAR,REAL) = REAL;
    add_result(REAL,CHAR) = add_result(CHAR,REAL);
    add_result(INTEGER,REAL) = REAL;
    add_result(REAL,INTEGER) = add_result(INTEGER,REAL);
    add_result(STRING,:) = STRING;
    add_result(:,STRING) = STRING;
    add_result(CELL,:) = NA; %Overwrites STRING entries
    add_result(:,CELL) = NA;
    
    %%
    % We also want to define a matrix for when the result type and one of
    % the operands is known. We will use 'NA' to indicate an invalid
    % combination, and 'NONE' to indicate an ambigous combination. The rows
    % correspond to the result type, and the columns to the operand.
    
    add_op = NaN*ones(NUM_TYPES);
    add_op(BOOLEAN,:) = NA;
    add_op(CHAR,:) = NA;
    add_op(INTEGER,:) = NA;
    add_op(INTEGER,INTEGER) = NONE;
    add_op(INTEGER,CHAR) = NONE;
    add_op(INTEGER,BOOLEAN) = NONE;
    add_op(REAL,:) = NA;
    add_op(REAL,CHAR) = REAL;
    add_op(REAL,INTEGER) = REAL;
    add_op(REAL,BOOLEAN) = REAL;
    add_op(REAL,REAL) = NONE;
    add_op(STRING,:) = STRING;
    add_op(STRING,STRING) = NONE;
    add_op(STRING,CELL) = NA;
    add_op(CELL,:) = NA;
            
    %%
    % Now we define convencience functions for modifying types.
    
    type_was_modified = true;
    
    function setType(node,type)
        nodes(DATA_TYPE,node) = type;
        type_was_modified = true;
    end
    
    function copyType(follower,leader)
        nodes(DATA_TYPE,follower) = nodes(DATA_TYPE,leader);
        type_was_modified = true;
    end
    
    function typeMatchNodes(node,child)
        if nodes(DATA_TYPE,node)~=NONE && nodes(DATA_TYPE,child)~=NONE && ...
                nodes(DATA_TYPE,node)~=DYNAMIC && nodes(DATA_TYPE,child)~=DYNAMIC
            assert(nodes(DATA_TYPE,node)==nodes(DATA_TYPE,child), 'Type mismatch.')
        elseif nodes(DATA_TYPE,node)~=NONE
            copyType(child, node)
        elseif nodes(DATA_TYPE,child)~=NONE
            copyType(node, child)
        end
    end

    function typeMatch(node,type)
        if type~=NONE
            if nodes(DATA_TYPE,node)~=NONE && nodes(DATA_TYPE,node)~=DYNAMIC
                assert(nodes(DATA_TYPE,node)==type, 'Type mismatch.')
            else
                assert(type~=NA, 'Type mismatch.')
                setType(node,type)
            end
        end
    end
    
    function descend = deduceTypes(node,parent)
        descend = true;
        type = nodes(NODE_TYPE,node);
        
        if type==ADD
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            if nodes(DATA_TYPE,lhs)~=NONE && nodes(DATA_TYPE,rhs)~=NONE
                typeMatch(node, add_result(nodes(DATA_TYPE,lhs),nodes(DATA_TYPE,rhs)))
            elseif nodes(DATA_TYPE,lhs)~=NONE && nodes(DATA_TYPE,node)~=NONE
                typeMatch(rhs, add_op(nodes(DATA_TYPE,node),nodes(DATA_TYPE,lhs)))
            elseif nodes(DATA_TYPE,rhs)~=NONE && nodes(DATA_TYPE,node)~=NONE
                typeMatch(lhs, add_op(nodes(DATA_TYPE,node),nodes(DATA_TYPE,rhs)))
            end
        elseif type==SUBTRACT || type==MULTIPLY || type==POWER || ...
                type==ELEM_POWER || type==ELEM_MULT
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            if nodes(DATA_TYPE,lhs)~=NONE && nodes(DATA_TYPE,rhs)~=NONE
                typeMatch(node, sub_result(nodes(DATA_TYPE,lhs),nodes(DATA_TYPE,rhs)))
            elseif nodes(DATA_TYPE,lhs)~=NONE && nodes(DATA_TYPE,node)~=NONE
                typeMatch(rhs, sub_op(nodes(DATA_TYPE,node),nodes(DATA_TYPE,lhs)))
            elseif nodes(DATA_TYPE,rhs)~=NONE && nodes(DATA_TYPE,node)~=NONE
                typeMatch(lhs, sub_op(nodes(DATA_TYPE,node),nodes(DATA_TYPE,rhs)))
            elseif nodes(DATA_TYPE,lhs)~=NONE
                typeMatch(node, sub_single(nodes(DATA_TYPE,lhs)));
            elseif nodes(DATA_TYPE,rhs)~=NONE
                typeMatch(node, sub_single(nodes(DATA_TYPE,rhs)));
            end
            
            if nodes(DATA_TYPE,node)~=NONE
                nodes(CAST_TYPE,lhs) = sub_cast(nodes(DATA_TYPE,node),1);
                nodes(CAST_TYPE,rhs) = sub_cast(nodes(DATA_TYPE,node),1);
                nodes(IMPLICIT_CAST,lhs) = sub_cast(nodes(DATA_TYPE,node),2);
                nodes(IMPLICIT_CAST,rhs) = sub_cast(nodes(DATA_TYPE,node),2);
            end
        elseif type==DIVIDE || type == ELEM_DIV
            %DO THIS
        elseif type==BACK_DIVIDE || type == ELEM_BACKDIV
            %DO THIS
        elseif type==EQUALS
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            typeMatchNodes(lhs,rhs); %DO THIS- allow setting a new type
        elseif type==IDENTIFIER
            %DO THIS
        elseif type==TRANSPOSE || type==COMP_CONJ || type==GROUPING
            child = nodes(UNARY_CHILD,node);
            typeMatchNodes(node,child);
        elseif type==UNARY_MINUS
            child = nodes(UNARY_CHILD,node);
            type = nodes(NODE_TYPE,node);
            ctype = nodes(NODE_TYPE,child);
            if type==STRING || ctype==STRING
                error('Undefined unary operator ''-'' for input arguments of type ''string''.')
            elseif type==CELL || ctype==CELL
                error('Undefined unary operator ''-'' for input arguments of type ''cell''.')
            elseif type==CHAR
                error('Result of unary minus cannot be of type ''char''.')
            elseif type==BOOLEAN
                error('Result of unary minus cannot be of type ''logical''.')
            elseif ctype==REAL
                typeMatch(node,REAL)
            elseif ctype==INTEGER || ctype==BOOLEAN || ctype==CHAR
                typeMatch(node,INTEGER)
            end
        elseif type==RANGE
            low = nodes(LHS,node);
            high = nodes(RHS,node);
            
            if nodes(DATA_TYPE,low)==INTEGER
                typeMatch(node, INTEGER)
            end
            
        elseif type==STEPPED_RANGE
            low = nodes(3,node);
            step = nodes(4,node);
            high = nodes(5,node);
            
            if nodes(DATA_TYPE,low)==INTEGER && nodes(DATA_TYPE,step)==INTEGER
                typeMatch(node, INTEGER)
            end
        elseif type==CALL
            %DO THIS
        elseif type==COLON
            %DO THIS
        elseif type==ARG_LIST
            %DO THIS
        elseif type==END
            setType(node,INTEGER)
        elseif type==CALL_STMT
            %DO THIS
        elseif type==EXPR_STMT
            %DO THIS
        elseif type==VERTICAT
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            %DO THIS
            
        elseif type==HORIZCAT
            lhs = nodes(LHS,node);
            rhs = nodes(RHS,node);
            
            %DO THIS
            
        elseif type==EMPTYMAT
            typeMatch(node,NA)
        elseif type==IF
            typeMatch(node,NA)
        elseif type==ELSEIF
            typeMatch(node,NA)
        elseif type==ELSE
            typeMatch(node,NA)
        elseif type==FOR
            typeMatch(node,NA)
        elseif type==PARFOR
            typeMatch(node,NA)
        elseif type==WHILE
            typeMatch(node,NA)
        elseif type==TRY
            typeMatch(node,NA)
        elseif type==CATCH
            typeMatch(node,NA)
        elseif type==GLOBAL
            typeMatch(node,NA)
        elseif type==PERSISTENT
            typeMatch(node,NA)
        elseif type==SPMD
            typeMatch(node,NA)
        elseif type==SWITCH
            typeMatch(node,NA)
        elseif type==CASE
            typeMatch(node,NA)
        elseif type==OTHERWISE
            typeMatch(node,NA)
        elseif type==DOT
            %DO THIS
        elseif type==CELL_CALL
            %DO THIS
        elseif type==META_CLASS
            %DO THIS
        elseif type==LAMBDA
            %DO THIS
        elseif type==FUNCTION_LAMBDA
            %DO THIS
        elseif type==FUN_REF
            %DO THIS
        elseif type==VAR_REF
            child = nodes(REF,node);
            typeMatchNodes(node,child);
        end
    end

    while type_was_modified
        type_was_modified = false;
        traverse(root,NONE,@deduceTypes,@deduceTypes);
    end
    
    %%
    % We need to alter the DOT code for the AST earlier so that we can
    % see the annotated tree.
    
    dot_name = [extensionless_name, '_annotated.dot'];
    dot_file = fopen(dot_name,'w');
    fprintf(dot_file,'digraph {\r\n\trankdir=TB\r\n\r\n');
    
    function descend = annotatedDotter(node,parent)
        descend = true;
        fprintf(dot_file,'\t');
        fprintf(dot_file,['node_', num2str(node), ' [label="']);
        fprintf(dot_file,[getLabel(node),'\\n']);
        fprintf(dot_file,['ID: ',num2str(node),'\\n']);
        if nodes(DATA_TYPE,node)~=NA && nodes(DATA_TYPE,node)~=FUNCTION
            if nodes(DATA_TYPE,node)~=DYNAMIC
                fprintf(dot_file,['Data Type: ', getTypeString(node),'\\n']);
            else
                fprintf(dot_file,'Data Type: Dynamic\\n');
            end
            fprintf(dot_file,['Cast Type: ', getCastTypeString(node),'\\n']);
            if nodes(ROWS,node)~=NONE
                fprintf(dot_file,['Rows: ', num2str(nodes(ROWS,node)),'\\n']);
            else
                fprintf(dot_file,'Rows: Unknown\\n');
            end
            if nodes(COLS,node) ~= NONE
                fprintf(dot_file,['Cols: ', num2str(nodes(COLS,node)),'\\n']);
            else
                fprintf(dot_file,'Cols: Unknown\\n');
            end
        end
        fprintf(dot_file,'"]\r\n');
        if parent~=NONE
            fprintf(dot_file,['\tnode_', num2str(parent), ...
                ' -> node_', num2str(node), '\r\n\r\n']);
        end
    end

    traverse(root,NONE,@annotatedDotter,@NO_POSTORDER);
    fprintf(dot_file,'}');
    fclose(dot_file);
    
    %%
    % We've given a good effort to statically deduce types and take thus
    % take full advantage of the compiler. However, we won't be able to
    % resolve every variable. As our final concession, we implement a
    % dynamically typed C++ class in 'lib/MatlabDynamicTyping'.
    
    %% Code Generation
    % Now our work has paid off, and we can iterate over the parse tree to
    % write the output code. We need to think about how we will map some of
    % the MATLAB constructs to C++.
    %
    % Unlike C++, MATLAB resolves all function definitions before resolving
    % other identifiers. That means you can call a function which is
    % defined later in the code without needing function prototypes, or in
    % our case declaring a lambda function. In C++, we need to define the
    % lambda functions before they are called. We also need to be careful
    % moving the lambda definitions around, because they still need to come
    % after the declarations of any variables they capture.
    %
    % The simplest way to get up and running is to declare all variables at
    % the top of a scope, including lambda functions, and under that define
    % the lambda functions (these are seperate steps to enable co-dependent
    % lambdas). This is not clean code, but it will get us up and running.
    % We can refine our declarations and lambda definitions in the future.
    %
    % For matrix variables and operations, we
    % will rely on the C++ matrix library "eigen" [4]. It supports
    % dynamically sized matrices, so in the general case functions will
    % accept variably-sized inputs, although hopefully we will be able to
    % deduce the size.
    %
    % Cells are a source of headache since the C++ standard library does
    % not have heterogenous containers. DO THIS
    %
    % Yet another issue to consider is the parse nodes whose sizes could
    % not be resolved. DO THIS
    
    %%
    % We'll start out by analzying the tree one last time to see which
    % constructs we'll need to include in the final code.
    
    has_unresolved_type = false;
    has_matrices = false;
    
    function descend = checkForIncludes(node,parent)
        descend = true;
        if nodes(DATA_TYPE,node)==NONE
            has_unresolved_type = true;
            setType(node,DYNAMIC)
        elseif nodes(DATA_TYPE,node)==REAL && ...
                (nodes(ROWS,node)~=1 || nodes(COLS,node)~=1)
            has_matrices = true;
        end
    end

    traverse(root,NONE,@checkForIncludes,@NO_POSTORDER);
    
    %%
    % We create the file into which we will write out C++ code.
    out = fopen(cpp_filename,'w');
    
    %%
    % Before we start generating code we define some convenience functions
    % to make this code generation section more readable:
    
    is_mex = false;
    
    tab_level = 0;
    function indent()
        for i = 1 : tab_level
            fprintf(out,'\t');
        end
    end

    function increaseIndentation()
        tab_level = tab_level + 1;
    end

    function decreaseIndentation()
        tab_level = tab_level - 1;
    end
    
    NEW_LINE = '\r\n';
    function writeNewline()
        fprintf(out, NEW_LINE);
    end

    function write(code)
        fprintf(out,code);
    end

    function writeLine(code)
        indent()
        write(code)
        writeNewline()
    end

    function writeComment(text)
        write(['//',text]);
        writeNewline()
    end

    function writeCommentLine(text)
        writeLine(['//',text]);
    end

    function writeBlockComment(text)
        write(['/*',text,'*/']);
        writeNewline()
    end
    
    has_extra_includes = false;
    function include(file)
        writeLine(['#include <',file,'>']);
        has_extra_includes = true;
    end

    function useNamespace(namespace)
        writeLine(['using namespace ',namespace,';']);
    end

    printing_opened = false;
    function startPrinting()
        indent()
        if is_mex
            write('mexPrintf( (');
        else
            write('std::cout << ')
        end
        
        printing_opened = true;
        increaseIndentation();
    end

    function stopPrinting()
        if is_mex
            write(').c_str() );')
        else
            write('" << std::endl;')
        end
        
        writeNewline()
        decreaseIndentation();
        printing_opened = false;
    end

    function printSeperator()
        if is_mex
            write('+');
        else
            write('<<')
        end
    end

    function printVarOut(name,node,close)
        if nodes(NODE_TYPE,node)==IGNORED_OUTPUT
            if printing_opened && close
                stopPrinting()
            end
            return
        end
        
        if ~printing_opened
            startPrinting()
        else
            if is_mex
                write(' +')
            else
                write('\\n" <<')
            end
            writeNewline()
            indent()
        end
        
        if is_mex
            if nodes(DATA_TYPE,node)==DYNAMIC
                write(['"\\n', name, ' =\\n\\n     " + '])
                printNode(node)
                write('.toString() + "\\n\\n"')
            else
                write(['"\\n', name, ' =\\n\\n     " + std::to_string('])
                printNode(node)
                write(') + "\\n\\n"')
            end
        else
            write(['"\\n',name,' = \\n\\n\\t" << '])
            printNode(node)
            write(' << "\\n')
        end
        
        if close
            stopPrinting()
        end
    end

    %%
    % MATLAB's rules for multi-output functions are much more flexible than
    % those of C++. In modern C++, a function can return a tuple, and you
    % can set several existing variables using an 'std::tie', or create
    % several new variables using structured binding. There isn't an
    % immediate way to have output arguments for some of the output
    % parameters like MATLAB allows, but we can easily avoid this by having
    % several dummy variables on hand to recieve ignored assignments.
    %
    % We create a class to ignore all assignments, along with a static
    % instance in file 'lib/IgnoredVariables'.
    % We are careful to use namespaces for all the extra variables we
    % define. Since MATLAB disallows colons in variable names, this
    % guarantees there will be no collisions between our translator
    % variable names and the user's source code.
    
    %%
    % Finally, let's write some code! We'll start out by including any
    % libraries we need:
    
    function writeIncludes()     
        if has_doc
            writeBlockComment([NEW_LINE, char(strrep(documentation,"%","")), NEW_LINE])
            writeNewline()
        end
        
        if is_mex
            writeLine('#include "mex.h"');
            writeNewline()
        end
        
        if has_unresolved_type
            include('MatlabDynamicTyping')
        end

        if has_matrices
            include('Eigen/Eigen/Dense')
            useNamespace('Eigen')
        end

        if program_prints_out || (is_mex && write_to_workspace)
            if ~is_mex
                include('iostream')
            else
                include('string') %for std::to_string
            end
            include('MatlabPrinting')
        end

        if uses_system
            include('stdlib.h')
        end

        if has_multi_output
            include('tuple')
        end
        
        if max_nesting_level > 1
            include('functional')
        end
        
        if has_ignored_outputs
            include('IgnoredOutput')
        end

        if has_extra_includes
            writeNewline()
        end
    end

    %%
    % MATLAB scripts may define functions, but in a C++ script we need to
    % define these before defining main().
    
    function writeFreeStandingFunctions()
        %Prototype then define base level functions
        curr = nodes(FIRST_SYMBOL,root);
        use_detail = (curr~=NONE && nodes(SYMBOL_LIST_LINK,curr)~=NONE && ~is_script && ~is_mex);
        
        if curr~=NONE
            prototypeBaseFunctions(curr);
            curr = nodes(SYMBOL_LIST_LINK,curr);
        end
        
        if use_detail
            write('namespace { ')
            writeComment("This achieves MATLAB-style encapsulation of secondary functions")
            increaseIndentation()
        end
        
        while curr~=NONE
            prototypeBaseFunctions(curr);
            curr = nodes(SYMBOL_LIST_LINK,curr);
        end
        writeNewline()
        
        
        curr = nodes(FIRST_SYMBOL,root);
        
        if use_detail
            defineBaseFunctions(curr);
            curr = nodes(SYMBOL_LIST_LINK,curr);
            curr = nodes(SYMBOL_LIST_LINK,curr);

            while curr~=NONE
                defineBaseFunctions(curr);
                curr = nodes(SYMBOL_LIST_LINK,curr);
            end
            decreaseIndentation()
            writeLine('}')
            writeNewline()
            defineBaseFunctions(main_func)
        else
            defineBaseFunctions(curr);
            curr = nodes(SYMBOL_LIST_LINK,curr);

            while curr~=NONE
                defineBaseFunctions(curr);
                curr = nodes(SYMBOL_LIST_LINK,curr);
            end
        end
    end
    
    %%
    % Now we move on to the body of our code. This just creates the
    % skeleton of our C++ code, but the real work will occur in a visitor
    % defined later.
    
    writeIncludes()
    writeFreeStandingFunctions()
    
    if is_script 
        writeLine('int main(){')
        increaseIndentation();
        
        %Declare the script level variables
        curr = nodes(FIRST_SYMBOL,root);
        while curr~=NONE
            declare(curr);
            curr = nodes(SYMBOL_LIST_LINK,curr);
        end
        
        if nodes(FIRST_SYMBOL,root)~=NONE
            writeNewline()
        end
        
        %Write the program
        printNode(root)
        fprintf(out,'\r\n');
        writeLine('return 0;')
        write('}');
    end
    
    %%
    % The bulk of effort in this section goes into another tree traversal
    % function which visits nodes in the correct order for writing the
    % code.
    
    function printBinaryNode(node,symbol)
        printNode(nodes(LHS,node))
        write(symbol);
        printNode(nodes(RHS,node))
    end

    function printLeftUnary(node, symbol)
        write(symbol);
        printNode(nodes(UNARY_CHILD,node))
    end
    
    function printNode(node)
        type = nodes(NODE_TYPE,node);
        
        if type==FUNCTION
            %DO NOTHING - functions needs to be handled before the body
        elseif type==ADD
            printBinaryNode(node,' + ')
        elseif type==SUBTRACT
            printBinaryNode(node,' - ')
        elseif type==MULTIPLY
            printBinaryNode(node, '*')
        elseif type==GREATER
            printBinaryNode(node, ' > ')
        elseif type==GREATER_EQUAL
            printBinaryNode(node, ' >= ')
        elseif type==LESS
            printBinaryNode(node, ' < ')
        elseif type==LESS_EQUAL
            printBinaryNode(node, ' <= ')
        elseif type==EQUALITY
            printBinaryNode(node, ' == ')
        elseif type==NOT_EQUAL
            printBinaryNode(node, ' != ')
        elseif type==NOT
            printLeftUnary(node, '!');
        elseif type==UNARY_MINUS
            printLeftUnary(node, '-');
        elseif type==SCALAR
            write(num2str(nodes(3,node)));
        elseif type==CHAR_ARRAY
            write(['''',readTextNode(node),''''])
        elseif type==STRING
            write(['"',readTextNode(node),'"'])
        elseif type==IDENTIFIER
            write(readTextNode(node));
        elseif type==VAR_REF
            printNode(nodes(REF,node))
        elseif type==IF
            writeIfStmt(node)
        elseif type==ELSEIF
            writeElseIfStmt(node)
        elseif type==ELSE
            writeElseStmt(node)
        elseif type==WHILE
            writeWhileStmt(node)
        elseif type==PARFOR
            writeParforStmt(node)
        elseif type==FOR
            writeForStmt(node)
        elseif type==SPMD
            writeSpmdStmt(node)
        elseif type==EQUALS
            writeAsgnStmt(node)
        elseif type==EXPR_STMT
            writeExprStmt(node)
        elseif type==BLOCK
            writeBlockStmt(node)
        elseif type==OS_CALL
            writeLine(['system("',readTextNode(node),'");'])
        elseif type==CALL_STMT
            writeCallStmt(node)
        elseif type==FUN_CALL
            writeFunCall(node)
        end
    end

    function printFunction(node)
        if nodes(SYMBOL_TREE_PARENT,node)~=NONE
            printLambdaFunction(node)
        end
    end

    function prototypeBaseFunctions(curr)
        if nodes(NODE_TYPE,curr)==FUNCTION
            prototypeBaseLevelFunction(curr)
        end
    end

    function defineBaseFunctions(curr)
        if nodes(NODE_TYPE,curr)==FUNCTION
            printBaseLevelFunctionDefinition(curr, true)
        end
    end

    function printLambdaFunction(node)
        indent();
        write([getName(node),' = [&]('])
        printFunctionInputList(nodes(FUN_INPUT,node));
        write('){')
        writeNewline()
        increaseIndentation();
        if nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,node))~=NONE
            printOutputDeclarations(nodes(FUN_OUTPUT,node));
            writeNewline()
        end
        printFunctionBody(node);
        if nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,node))~=NONE
            writeNewline()
            printOutputReturn(nodes(FUN_OUTPUT,node));
        end
        decreaseIndentation();
        writeLine('};')
        writeNewline()
    end

    function writeIfStmt(node)
        indent();
        write('if(');
        printNode(nodes(3,node));
        write('){');
        writeNewline();
        increaseIndentation();
        printNode(nodes(4,node));
        decreaseIndentation();

        if nodes(5,node)~=NONE
            indent();
            write('}');
            printNode(nodes(5,node));
        else
            writeLine('}')
            writeNewline()
        end
    end

    function writeElseIfStmt(node)
        write('else if(');
        printNode(nodes(3,node));
        write('){');
        writeNewline()
        increaseIndentation()
        printNode(nodes(4,node));
        decreaseIndentation()

        if nodes(5,node)~=NONE
            indent()
            write('}')
            printNode(nodes(5,node));
        else
            writeLine('}')
            writeNewline()
        end
    end

    function writeElseStmt(node)
        write('else{');
        writeNewline()
        increaseIndentation()
        printNode(nodes(3,node));
        decreaseIndentation()
        writeLine('}')
        writeNewline()
    end

    function writeWhileStmt(node)
        indent()
        write('while(')
        printNode(nodes(LHS,node))
        write('){')
        writeNewline()
        increaseIndentation()
        printNode(nodes(RHS,node))
        decreaseIndentation()
        writeLine('}')
        writeNewline()
    end

    function writeParforStmt(node)
        writeLine('#pragma omp parallel for')
        writeForStmt(node)
        %DO THIS - openmp requires additional restrictions, e.g. the
        %counter must be an integer, and must be compared to an integer
    end

    function writeForStmt(node)
        indent()
        write('for(')
        
        assignment = nodes(LHS,node);
        iterator_name = nodes(LHS,assignment);
        range = nodes(RHS,assignment);
        
        %The type is declared in the body of the function. This isn't good
        %C++ practice, but it matches Matlab's ability to use the iterator
        %variable after the loop has ended.
        write([getName(iterator_name),' = '])
        printNode(nodes(3,range))
        write('; ')
        
        if nodes(NODE_TYPE,range)==STEPPED_RANGE
            %DO THIS - need to know if the step is positive or negative
        else
            write([getName(iterator_name),' <= '])
            printNode(nodes(4,range))
            write(['; ',getName(iterator_name),'++'])
        end
        
        write('){')
        writeNewline()
        increaseIndentation()
        printNode(nodes(RHS,node))
        decreaseIndentation()
        writeLine('}')
        writeNewline()
    end

    function writeSpmdStmt(node)
        %DO THIS - proper printing is nearly impossible
        %need to redirect output streams
        %
        %With some hacking, you could check if output is used, define
        %streams for each thread, and have the streams print out after the
        %spmd tasks finish.
        writeLine('#pragma omp parallel')
        writeLine('{')
        increaseIndentation()
        writeBlockStmt(node)
        decreaseIndentation()
        writeLine('}')
        writeNewline()
    end

    function name = getName(node)
        if nodes(NODE_TYPE,node)==VAR_REF
            name = readTextNode(nodes(REF,node));
        elseif nodes(NODE_TYPE,node)==FUN_REF
            name = getName(nodes(REF,node));
        elseif nodes(NODE_TYPE,node)==FUNCTION
            if is_script || is_mex || node==main_func || nodes(SYMBOL_TREE_PARENT,node)~=NONE
                name = readTextNode(nodes(FUN_NAME,node));
            else
                name = ['detail::',readTextNode(nodes(FUN_NAME,node))];
            end
        elseif nodes(NODE_TYPE,node)==IDENTIFIER || nodes(NODE_TYPE,node)==FUN_IDENTIFIER
            name = readTextNode(node);
        else
            name = '#FAILED_NAME_LOOKUP#';
        end
    end

    function writeAsgnStmt(node)
        indent();
        printBinaryNode(node,' = ')
        write(';')
        writeNewline()
        if nodes(VERBOSITY,node)
            name = getName(nodes(LHS,node));
            printVarOut(name,nodes(LHS,node),true)
        end
    end

    function writeExprStmt(node)
        if nodes(VERBOSITY,node)
            printVarOut('ans',nodes(UNARY_CHILD,node),true)
        else
            indent()
            printNode(nodes(UNARY_CHILD,node));
            write(';')
            writeNewline()
        end
    end

    function writeBlockStmt(node)
        stmt = nodes(FIRST_BLOCK_STATEMENT,node);
        
        while stmt~=NONE
            printNode(stmt);
            stmt = nodes(LIST_LINK,stmt);
        end
    end

    function writeCallStmt(node)
        ref = nodes(6,node);
        fun = nodes(REF,ref);
        out_param = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,fun));
        out_arg = nodes(FIRST_PARAMETER,nodes(LHS,node));
        
        if ~(out_arg==NONE && out_param~=NONE && nodes(VERBOSITY,node)==1)
            indent()
        end
        
        use_get = false;
        if nodes(FIRST_PARAMETER,nodes(LHS,node))~=NONE
            num_out_params = 0;
            num_out_args = 0;
            num_ignored = 0;
            out_arg = nodes(FIRST_PARAMETER,nodes(LHS,node));
            while out_arg~=NONE
                num_out_args = num_out_args + 1;
                num_ignored = num_ignored + (nodes(NODE_TYPE,out_arg)==IGNORED_OUTPUT);
                out_arg = nodes(LIST_LINK,out_arg);
            end
            ref = nodes(6,node);
            fun = nodes(REF,ref);
            out_param = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,fun));
            while out_param~=NONE
                num_out_params = num_out_params + 1;
                out_param = nodes(LIST_LINK,out_param);
            end
            
            out_arg = nodes(FIRST_PARAMETER,nodes(LHS,node));
            out_param = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,fun));
            
            if num_out_args > num_out_params
                error(['Error using ',getName(LHS,node)],...
                'Too many output arguments');
            elseif num_out_args == num_out_params
                if num_out_args > 1 && num_ignored < num_out_args
                    write('std::tie(')

                    if nodes(NODE_TYPE,out_arg)~=IGNORED_OUTPUT
                        write(getName(out_arg))
                    else
                        write('IGNORED::OUTPUT')
                    end
                    out_arg = nodes(LIST_LINK,out_arg);
                    while out_arg~=NONE
                        write(', ')
                        if nodes(NODE_TYPE,out_arg)~=IGNORED_OUTPUT
                            write(getName(out_arg))
                        else
                            write('IGNORED::OUTPUT')
                        end
                        out_arg = nodes(LIST_LINK,out_arg);
                    end
                    write(') = ')
                elseif nodes(NODE_TYPE,out_arg)~=IGNORED_OUTPUT
                    write(getName(out_arg))
                    write(' = ')
                end
            else
                if num_out_args > 1 && num_ignored < num_out_args
                    %Use subset of tuple result to make multi-output assignment
                    write('std::tie(')

                    if nodes(NODE_TYPE,out_arg)~=IGNORED_OUTPUT
                        write(getName(out_arg))
                    else
                        write('IGNORED::OUTPUT')
                    end
                    out_arg = nodes(LIST_LINK,out_arg);
                    out_param = nodes(LIST_LINK,out_param);
                    while out_arg~=NONE
                        write(', ')
                        if nodes(NODE_TYPE,out_arg)~=IGNORED_OUTPUT
                            write(getName(out_arg))
                        else
                            write('IGNORED::OUTPUT')
                        end
                        out_arg = nodes(LIST_LINK,out_arg);
                        out_param = nodes(LIST_LINK,out_param);
                    end
                    while out_param~=NONE
                        write(', IGNORED::OUTPUT')
                        out_param = nodes(LIST_LINK,out_param);
                    end
                    write(') = ')
                elseif nodes(NODE_TYPE,out_arg)~=IGNORED_OUTPUT
                    write([getName(out_arg),' = std::get<0>('])
                    use_get = true;
                end
            end
        end
        
        ref = nodes(6,node);
        fun = nodes(REF,ref);
        out_param = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,fun));
        out_arg = nodes(FIRST_PARAMETER,nodes(LHS,node));
        
        if ~(out_arg==NONE && out_param~=NONE && nodes(VERBOSITY,node)==1)
            write([getName(nodes(6,node)),'('])
            writeArgs(nodes(RHS,node))
            if use_get
                write(')')
            end
            write(');')
            writeNewline()
        else
            startPrinting()
            write('"\\nans =\\n\\n     " ')
            printSeperator()
            if is_mex && nodes(LIST_LINK,out_param)~=NONE
                if nodes(DATA_TYPE,out_param)==DYNAMIC
                    write([' std::get<0>(',getName(nodes(6,node)),'('])
                    writeArgs(nodes(RHS,node))
                    write(')).toString() ')
                else
                    write([' std::to_string(std::get<0>(',getName(nodes(6,node)),'('])
                    writeArgs(nodes(RHS,node))
                    write('))) ')
                end
                
                printSeperator()
                write(' "\\n\\n"')
            elseif nodes(LIST_LINK,out_param)~=NONE
                write([' std::get<0>(',getName(nodes(6,node)),'('])
                writeArgs(nodes(RHS,node))
                write(')) ')
                printSeperator()
                write(' "\\n')
            elseif is_mex
                if nodes(DATA_TYPE,out_param)==DYNAMIC
                    write([' ',getName(nodes(6,node)),'('])
                    writeArgs(nodes(RHS,node))
                    write(').toString() ')
                else
                    write([' std::to_string(',getName(nodes(6,node)),'('])
                    writeArgs(nodes(RHS,node))
                    write(')) ')
                end

                printSeperator()
                write(' "\\n\\n"')
            else
                write([' ',getName(nodes(6,node)),'('])
                writeArgs(nodes(RHS,node))
                write(') ')
                printSeperator()
                write(' "\\n')
            end
            
            stopPrinting()
        end
        
        
        
        if nodes(VERBOSITY,node)==1 && ...
                nodes(FIRST_PARAMETER,nodes(LHS,node))~=NONE
            out_arg = nodes(FIRST_PARAMETER,nodes(LHS,node));
            
            while out_arg~=NONE
                name = getName(out_arg);
                printVarOut(name,out_arg,nodes(LIST_LINK,out_arg)==NONE)
                out_arg = nodes(LIST_LINK,out_arg);
            end
        end
    end

    function writeFunCall(node)
        use_get = false;
        ref = nodes(LHS,node);
        fun = nodes(REF,ref);
        out_param = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,fun));
        
        if out_param==NONE
            error(['Error using ',getName(LHS,node)],...
                'Too many output arguments');
        end
            
        if nodes(LIST_LINK,out_param)~=NONE
            write('std::get<0>(');
            use_get = true;
        end
            
        write([getName(nodes(LHS,node)),'('])
        writeArgs(nodes(RHS,node))
        if use_get
            write(')')
        end
        write(')')
    end

    function writeArgs(node)
        arg = nodes(FIRST_PARAMETER,node);
        if arg~=NONE
            printNode(arg);
            arg = nodes(LIST_LINK,node);
        end
        while arg~=NONE
            write(', ')
            printNode(arg);
            arg = nodes(LIST_LINK,node);
        end
    end

    function declare(node)
        if nodes(NODE_TYPE,node)==FUNCTION
            if nodes(SYMBOL_TREE_PARENT,node)~=NONE
                declareLambda(node)
            end
        else
            writeLine([getTypeString(node), ' ', readTextNode(node), ';'])
        end
    end

    function declareLambda(node)
        indent()
        write('std::function<');
        printOutputType(nodes(FUN_OUTPUT,node));
        write('(')

        input = nodes(FIRST_PARAMETER,nodes(FUN_INPUT,node));
        if input~=NONE
            write(getTypeString(input))

            while nodes(LIST_LINK,input)~=NONE
                write(', ');
                input = nodes(LIST_LINK,input);
                write(getTypeString(input))
            end
        end

        write(')')
        write(['> ', getName(node),';'])
        writeNewline()
    end

    function prototypeBaseLevelFunction(curr)
        outsize = printOutputType(nodes(FUN_OUTPUT,curr));
        write([' ', getName(curr), '(']);
        printFunctionInputList(nodes(FUN_INPUT,curr));
        write(');');
        writeNewline()
    end
    
    function printBaseLevelFunctionDefinition(curr, break_after)
        indent();
        outsize = printOutputType(nodes(FUN_OUTPUT,curr));
        write([' ', getName(curr), '(']);
        printFunctionInputList(nodes(FUN_INPUT,curr));
        write('){');
        writeNewline()
        increaseIndentation()
        
        if outsize > 0
            printOutputDeclarations(nodes(FUN_OUTPUT,curr));
            writeNewline()
        end
        
        printFunctionBody(curr)
        
        if outsize > 0
            writeNewline()
            printOutputReturn(nodes(FUN_OUTPUT,curr));
        end
        
        decreaseIndentation()
        indent();
        fprintf(out,'}');
        if break_after
            fprintf(out,'\r\n\r\n');
        end
    end

    function printFunctionBody(node)
        if nodes(FIRST_SYMBOL,node)~=NONE
            printWorkspaceDeclarations(nodes(FIRST_SYMBOL,node));
            writeNewline()
        end
        
        defineLambdas(node);
        
        printNode(nodes(FUN_BODY,node));
    end

    function defineLambdas(node)
        traverse(nodes(FUN_BODY,node),node,@defineLambda,@NO_POSTORDER);
    end

    function keep_going = defineLambda(node,parent)
        keep_going = true;
        
        if nodes(NODE_TYPE,node)==FUNCTION
            printFunction(node)
            keep_going = false;
        end
    end

    function size = printOutputType(node)
        output = nodes(FIRST_PARAMETER,node);
        
        if output == NONE
            write('void');
            size = 0;
        else
            if nodes(LIST_LINK,output)==NONE
                write(getTypeString(output));
                size = 1;
            else
                write('std::tuple<');
                write(getTypeString(output));
                while nodes(LIST_LINK,output)~=NONE
                    write(', ');
                    output = nodes(LIST_LINK,output);
                    write(getTypeString(output));
                end
                write('>');
                size = 2;
            end
        end
    end

    function printOutputDeclarations(node)
        output = nodes(FIRST_PARAMETER,node);
        
        while output ~= NONE
            declare(output)
            output = nodes(LIST_LINK,output);
        end
    end

    function printWorkspaceDeclarations(node)
        while node~=NONE
            declare(node)
            node = nodes(SYMBOL_LIST_LINK,node);
        end
    end

    function printOutputReturn(node)
        output = nodes(FIRST_PARAMETER,node);
        
        if output ~= NONE
            if nodes(LIST_LINK,output)==NONE
                writeLine(['return',' ',readTextNode(output), ';'])
            else
                indent()
                write('return std::tuple<');
                write(getTypeString(output));
                while nodes(LIST_LINK,output)~=NONE
                    write(', ');
                    output = nodes(LIST_LINK,output);
                    write(getTypeString(output));
                end
                write('>(');
                
                output = nodes(FIRST_PARAMETER,node);
                write(readTextNode(output));
                while nodes(LIST_LINK,output)~=NONE %DO THIS - symbol table is inadequate
                    write(', ')
                    output = nodes(LIST_LINK,output);
                    write(readTextNode(output))
                end
                write(');')
                writeNewline()
            end
        end
    end

    function printFunctionInputList(node)
        input = nodes(FIRST_PARAMETER,node);
        
        if input~=NONE
            write([getTypeString(input),' ',readTextNode(input)])
            
            while nodes(LIST_LINK,input)~=NONE
                write(', ');
                input = nodes(LIST_LINK,input);
                write([getTypeString(input),' ',readTextNode(input)])
            end
        end
    end
    
    fclose(out);
    
    
    %%
    % We also want to translate to MEX code:
    
    is_mex = true;
    out = fopen([mex_filename,'.cpp'],'w');
    tab_level = 0;
    
    writeIncludes()
    writeFreeStandingFunctions()
    
    writeLine('void mexFunction( int nlhs, mxArray *plhs[], int nrhs, mxArray *prhs[] ){');
    increaseIndentation();
    
    if is_script
        writeLine(['if(nrhs > 0 || nlhs > 0) mexErrMsgTxt("Attempt to execute SCRIPT',' ', mex_filename, ' ', 'as a function");']);
        writeNewline()
        
        writeCommentLine('Declare base-workspace variables')
        curr = nodes(FIRST_SYMBOL,root);
        num_vars = 0;
        while curr~=NONE
            declare(curr);
            if nodes(NODE_TYPE,curr)==IDENTIFIER
                num_vars = num_vars + 1;
            end
            curr = nodes(SYMBOL_LIST_LINK,curr);
        end
        
        if nodes(FIRST_SYMBOL,root)~=NONE
            writeNewline()
        end
        
        writeCommentLine('Translated script')
        printNode(root)
        
        if write_to_workspace && num_vars > 0
            writeNewline()
            writeCommentLine('Update workspace-level variables')
            indent()
            curr = nodes(FIRST_SYMBOL,root);
            write('mexEvalString((')
            if num_vars == 1
                while curr~=NONE
                    if nodes(NODE_TYPE,curr)==IDENTIFIER
                        write(getMatlabAssignmentString(curr))
                    end
                    
                    curr = nodes(SYMBOL_LIST_LINK,curr);
                end
            else
                writeNewline()
                increaseIndentation()

                while curr~=NONE
                    if nodes(NODE_TYPE,curr)==IDENTIFIER
                        writeLine(getMatlabAssignmentString(curr))
                    end
                    
                    curr = nodes(SYMBOL_LIST_LINK,curr);
                end
                
                decreaseIndentation()
                indent()
            end
            
            write(').c_str());')
            writeNewline()
        end
    else
        num_inputs = 0;
        input = nodes(FIRST_PARAMETER, nodes(FUN_INPUT,main_func));
        while input~=NONE
            num_inputs = num_inputs + 1;
            input = nodes(LIST_LINK, input);
        end
        
        writeCommentLine('Validate IO')
        if num_inputs > 0
            writeLine(['if(nrhs < ',num2str(num_inputs),') mexErrMsgTxt("Not enough input arguments.");']);
        end
        writeLine(['if(nrhs > ',num2str(num_inputs),') mexErrMsgTxt("Too many input arguments.");']);
        
        num_outputs = 0;
        output = nodes(FIRST_PARAMETER, nodes(FUN_OUTPUT,main_func));
        while output~=NONE
            num_outputs = num_outputs + 1;
            output = nodes(LIST_LINK, output);
        end
        writeLine(['if(nlhs > ',num2str(num_outputs),') mexErrMsgTxt("Too many output arguments.");']);
        writeNewline()
        
        if num_inputs > 0
            writeCommentLine('Parse MEX inputs')
        end
        input = nodes(FIRST_PARAMETER,nodes(FUN_INPUT,main_func));
        num_inputs = 0;
        while input~=NONE
            parseMexInput(input,num_inputs)
            num_inputs = num_inputs + 1;
            input = nodes(LIST_LINK,input);
        end
        if num_inputs > 0
            writeNewline()
        end
        
        writeCommentLine('Call the main function')
        indent()
        var = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,main_func));
        
        if var~=NONE && nodes(LIST_LINK,var)~=NONE
            write(['auto& [',getName(var)])
            var = nodes(LIST_LINK,var);
            while var~=NONE
                write([', ',getName(var)])
                var = nodes(LIST_LINK,var);
            end
            write('] = ')
        elseif var~=NONE
            write([getTypeString(var),' ',getName(var),' = '])
        end
        write([getName(main_func),'('])
        
        var = nodes(FIRST_PARAMETER,nodes(FUN_INPUT,main_func));
        if var~=NONE
            write(getName(var))
            var = nodes(LIST_LINK,var);
        end
        while var~=NONE
            write([', ',getName(var)])
            var = nodes(LIST_LINK,var);
        end
        write(');')
        writeNewline()
        writeNewline()
        
        if num_outputs > 0
            writeCommentLine('Transfer output to MEX lhs')
        end
        output = nodes(FIRST_PARAMETER,nodes(FUN_OUTPUT,main_func));
        num_outputs = 0;
        while output~=NONE
            parseMexOutput(output,num_outputs)
            num_outputs = num_outputs + 1;
            output = nodes(LIST_LINK,output);
        end
    end
    
    write('}');
    
    fclose(out);
    
    function parseMexInput(input,num)
        if nodes(DATA_TYPE,input)==DYNAMIC
            writeLine(['Matlab::DynamicType ', getName(input), '(prhs[',num2str(num),']);']);
        elseif nodes(DATA_TYPE,input)==REAL
            writeLine(['if(~mxIsDouble(prhs[',num2str(num),']))',...
                ' mexErrMsgTxt("Expected argument ',num2str(num),' to be of type double.");'])
            writeLine(['double ', getName(input), ' = mxGetScalar(prhs[',num2str(num),'])']);
        else
            error('Unhandled input case.')
        end
    end

    %%
    % We should pause to appreciate the fact that we have added another
    % level-- we are now writing code, to write code, to write code. That
    % is writing code in MATLAB, to write code in C++, to write code in
    % MATLAB.

    function parseMexOutput(output,num)        
        if nodes(DATA_TYPE,output)==DYNAMIC
            writeLine([getName(output),'.setMatlabValue(plhs[',num2str(num),']);'])
        elseif nodes(DATA_TYPE,output)==REAL || nodes(DATA_TYPE,output)==INTEGER
            writeLine(['plhs[',num2str(num),'] = mxCreateDoubleMatrix(1, 1, mxREAL);'])
            writeLine(['double* output',num2str(num),' = mxGetPr(plhs[',num2str(num),']);'])
            writeLine(['output',num2str(num),'[0] = ',getName(output),';'])
        else
            error('Unhandled output case.')
        end
    end

    function string = getMatlabAssignmentString(node)
        name = getName(node);
        type = nodes(DATA_TYPE,node);
        if type==REAL || type==INTEGER
            string = ['"',name,'=" + std::to_string(',name,') + ";"'];
        elseif type==CHAR
        	string = ['"',name,'=''" + ',name,' + "'';"'];
        elseif type==BOOLEAN
            string = ['"',name,'=" + Matlab::boolToString(',name,') + ";"'];
        elseif type==STRING
            string = ['"',name,'=\\"" + ',name,' + "\\";"'];
        elseif type==DYNAMIC
            string = '"name=" + name.getMatlabAssignmentString() + ";"';
        else
            string = "#UNHANDLED ASGN STRING#";
        end
    end
    
    %%
    % And of course, we wouldn't want to forget the help file to go along
    % with our MEX function:
    
    if has_doc
        out = fopen([mex_filename,'.m'],'w');
        fprintf(out, strrep(documentation,"%","%%"));
        fprintf(out, "\r\n%%\r\n%%(This file has been translated to MEX.)");
        fclose(out);
    end
    
    %% Bootstrapping
    % Now that we have a fully working translator, we might as well
    % translate it to a MEX function so it will run faster. Just type
    % 'translateToCpp17(-DO THIS-)' into the MATLAB command window.
    
    %% Awknowledgements
    % I would like to thank Bob Nystrom for his excellent book "Crafting
    % Interpreters" [5] (which is free online, although I personally plan
    % on buying the print version when available).
    
    %% References
    % # <https://www.mathworks.com/help/matlab/matlab_prog/matlab-operators-and-special-characters.html MATLAB Operators and Special Characters>
    % # <https://www.mathworks.com/help/matlab/matlab_prog/operator-precedence.html Operator Precedence>
    % # <https://www.mathworks.com/help/matlab/class-definition-and-organization.html Class Definition and Organization>
    % # <https://www.mathworks.com/help/releases/R2017a/matlab/matlab_prog/nested-functions.html Nested Functions>
    % # <https://www.mathworks.com/help/matlab/ref/global.html Global Variables>
    % # <https://www.mathworks.com/help/matlab/ref/persistent.html Persistent Variables>
    % # <http://eigen.tuxfamily.org/index.php?title=Main_Page Eigen C++ Matrix Library>
    % # <http://craftinginterpreters.com Crafting Interpreters>
end