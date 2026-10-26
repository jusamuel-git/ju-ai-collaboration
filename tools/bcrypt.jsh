import org.springframework.security.crypto.bcrypt.BCrypt;
System.out.println("HASH=" + BCrypt.hashpw(System.getenv("SMOKE_PW"), BCrypt.gensalt(10)));
/exit
