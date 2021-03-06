#Number for the starting 1st octet
first = 172

#Define the range for the 2nd octect.
start_second = 16
end_second = 16

#Define the range of /24 subnets for the 3rd octet
start_third = 0
end_third = 2

#Number of /32 hosts per /24 prefix. The code example assumes that .1 will be the first address.
num_hosts = 5

#Creates a new text file "write.txt"
text_file = open("write.txt", "w")

#Second octet starting number
second_octet = start_second

#If second octet is equal or less than value of the end_second variable continue with the next Loop
while second_octet <= end_second:
    second = str(second_octet)
    third_octet = start_third

    #If the third octet is equal or less than the end_third variable continue with the next loop
    while third_octet <= end_third:
        third = str(third_octet)
        last_octet = 1

        #If the last octet is equal or less than the num_host than write the current IP Address to File
        while last_octet <= num_hosts:
            last = str(last_octet)
            text_file.write("ip route "+str(first)+"."+second+"."+third+"."+last+" 255.255.255.255 Null0\n")
            last_octet += 1
        third_octet += 1
    second_octet += 1
#At the end when the loops finish based on the conditions close the File.
text_file.close()

# Opening a file
file = open("write.txt", "r")
Counter = 0

# Reading from file
Content = file.read()
CoList = Content.split("\n")

for i in CoList:
    if i:
        Counter += 1

print("Static routes generated:", Counter)
