resource "aws_internet_gateway" "igwtf" {
  vpc_id = aws_vpc.vpctf.id

  tags = {
    Name  = "igw-tf",
    Owner = "VietAWS"
  }
}