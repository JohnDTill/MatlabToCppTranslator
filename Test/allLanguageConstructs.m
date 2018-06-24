%This function aims to include all token types and parse rules.
%Currently classdef is excluded.

function [a,b,c] = allLanguageConstructs(x,y,z)
    thing = 1 + 2 - 3 * 4 / 5 \ 6 ^ 7 .* 8 ./ 9 .\ 10;
    a = x' * ...
        1e-2.'
    !echo
    b = (thing+1)/2;
    c = 1.^-2 : 3 : 5 : 7;
    d = -1 + ~0;
    e = 1 > 0 | 2 >= 1 || 3 < 2 & 5 <= 10 && 1==1 | 0~=1;
    f = eye(3);
    g = f(:,end-1);
    
    plot(1+2,3+4);
    
    h = [1, 2; 3 4+5]; %Test reasonable concatination
    i = []; %Test empty concatination
    [j,~] = size(eye(3)); %Test func stmt w/ ignored output argument
    k = [1,2,;; %Test valid outlandish syntax
        ,;3 4]
    l = [1,] + [2;]; %More crazy syntax
    
    %Repeat w/ cell concatination
    h = {1, 2; [3,4] 5+6}; %Test reasonable concatination
    i = {}; %Test empty concatination
    k = {1,2,;; %Test valid outlandish syntax
        ,;3 4}
    l = {1,;}; %More crazy syntax
    
    m = 'hello' + "world"; %Test string and char array
    n = ''; %Test empty string
    
    if 2 > 1, disp('hello'); elseif 3>1, disp('world'); else
        disp('goodbye')
    end
    while b < 5
        b = b + 1
    end
    for i = 1 : 5
        disp(i)
        break
    end
    parfor i = 1 : 5
        disp(i)
        continue
    end
    spmd a = 1+1
        b = 2+2
        c = 3+3
    end
    try
        error('Test')
    end
    try error('Another Test')
    catch
        disp('Caught!')
    end
    try error('Another Test')
    catch some_excep
        disp('Caught!')
    end
    global xx yy zz; persistent xxx yyy zzz;
    
    switch 1
        case 1
            disp(1)
        case 2
        otherwise
            disp(3)
    end
    
    switch 2
    end
    
    a = struct('b',1);
    c = a.b
    e = k{:,1};
    
    f = ?inputParser
    b = @sin;
    c = @(t) t^2 + t - 1;
    1+2
    
    a.b = 5;
    
    return
end