# NAT 1
resource "aws_eip" "nat1" {
  domain = "vpc"
  tags = {
    Name = "nat1-eip"
  }
}

resource "aws_nat_gateway" "nat1" {
  allocation_id = aws_eip.nat1.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "nat1-tf"
  }

  depends_on = [aws_internet_gateway.igwtf]
}

# NAT 2
# resource "aws_eip" "nat2" {
#   domain = "vpc"
#   tags = {
#     Name = "nat2-eip"
#   }
# }

# resource "aws_nat_gateway" "nat2" {
#   allocation_id = aws_eip.nat2.id
#   subnet_id     = aws_subnet.public_1b.id

#   tags = {
#     Name = "nat2-tf"
#   }

#   depends_on = [aws_internet_gateway.igwtf]
# }