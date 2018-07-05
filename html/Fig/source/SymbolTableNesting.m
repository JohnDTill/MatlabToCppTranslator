a = 2;
b = 3;
e = 4;
function outer()
	a = 1;
	function fun1()
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
			d = 4;
		end
		funA();
	end
	e = 2;
end