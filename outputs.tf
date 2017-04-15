#output "address" {
#  value = "${aws_elb.web.dns_name}"
#}

output "ip" {
  value = "${aws_instance.web.public_ip}"
}
