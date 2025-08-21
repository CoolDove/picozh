set p8file=C:\Users\Administrator\AppData\Roaming\pico-8\carts\trypicozh.p8
set p8file2=D:\workspc\pico-8\trypicozh.p8

if exist "%p8file1%" (
    set "p8file=%p8file1%"
) else if exist "%p8file2%" (
    set "p8file=%p8file2%"
)

picozh "The Secret of Psalm 46.md" -p8 %p8file% --sprite-page:1 --sprite-page:2 --sprite-page:3 -unknown-char " "