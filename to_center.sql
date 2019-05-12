CREATE OR REPLACE FUNCTION common.to_center(str character varying, max_length integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE _res CHARACTER VARYING := ''; -- результат
		_length integer; -- длина строки
		_str CHARACTER VARYING := str; -- редактируемая строка
		_symbol CHARACTER VARYING := ' '; -- символ разделитель
		_str_left integer := 0; -- левая часть строки
		_str_right integer := 0; -- правая часть строки
		_spaces integer := 0; -- кол-во пробелов
		_spaces_left integer := 0; -- кол-во пробелов слева
		_spaces_right integer := 0; -- кол-во пробелов справа
		_res_counter CHARACTER VARYING := ''; -- конкатенируемая строка для проверки
BEGIN
--	SELECT * FROM common.to_center('Перец & Яковлев. Дудь, Колыма и репрессии. Закрыли тему.fdsf', 50);

	LOOP
		_str := (SELECT common.split_string(_str, max_length, TRUE));
		_res_counter := _res_counter || ' ' || _str;
		_length := (SELECT length(_str));
	
		_str_left := _length / 2;
		_str_right := _length - _str_left; 
		_spaces := max_length - _length;
		_spaces_left := _spaces / 2;
		_spaces_right := _spaces - _spaces_left;
		_res := _res ||  lpad(LEFT(_str, _str_left), max_length / 2, _symbol) 
				|| rpad(RIGHT(_str, _str_right), max_length - max_length / 2, _symbol) 
			    || chr(10);
			
		IF length(_res_counter) >= length(str) THEN
			EXIT;
		END IF;
		_str := RIGHT(str, length(str) - length(_res_counter));
	
	END LOOP;

	
	return _res;
END;
$function$
;
