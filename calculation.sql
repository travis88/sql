CREATE OR REPLACE FUNCTION calculation.subsidy(_calc uuid, _begin date, _end date, _calc_array character varying)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE rec record; -- итерация цикла
		_case uuid; -- дело
		_b_enabled boolean;
		_b_sampled_recalculated boolean;
		_c_subsidy_type CHARACTER VARYING; -- вид субсидии
		_n_last_calc_day integer; -- последнее расчётное число месяца
		_f_district integer; -- район
		_f_settlement integer; -- поселение
		_n_maximum_share_cost numeric(10, 2); -- максимально допустимая доля расходов
	
		_count_location integer; -- кол-во зарегистрированных пмж
		_count_place_stay integer; -- кол-во зарегистрированных пмп
		_count_other_address integer; -- кол-во зарегистрированных по другому адресу
		_count_temp_absent integer; -- кол-во временно отсутствующих
		_count_family_members integer; -- кол-во членов семьи
		_count_employees integer; -- кол-во трудоспособных
		_count_pensioners integer; -- кол-во пенсионеров
		_count_children integer; -- кол-во детей
		_average_month_income numeric(10, 2); -- среднемесячный совокупный доход семьи в расчётном периоде
		_percapita_income numeric(10, 2); -- среднедушевой доход семьи в расчётном периоде
		_n_republic_area numeric(10, 2) := 0; -- социальная норма площади жилого помещения
		
		--+++++++++++++++++++++++++--
		--     ТВЁРДОЕ ТОПЛИВО     --
		--+++++++++++++++++++++++++--
		_n_annual_volume NUMERIC; -- годовой объём твёрдого топлива
		_n_months NUMERIC(10, 4); -- кол-во месяцев по нормативу
		_n_sol_months integer; -- кол-во целых месяцев
		_n_days_in_month integer; -- кол-во дней в последнем месяце
		_n_fact_payment_year NUMERIC(10, 2); -- размер фактических расходов на оплату ТТ с учётом льгот 
		_n_fact_payment_month NUMERIC(10, 2); -- размер среднемесячных расходов на оплату тт с учётом льгот
		_n_rest_volume NUMERIC; -- неиспользованный остаток
		_n_normative_cost NUMERIC; -- нормативные расходы
		
		_n_owners_share numeric; -- общая доля всех собственников
		_n_normative_year numeric; -- норматив потребления ТТ на год
		_n_volume numeric; -- приобретённый объем твёрдого топлива
		_n_fuel_payment numeric(10, 2); -- фактические расходы на твёрдое топливо
		_n_fuel_discount numeric(10, 2); -- льгота на оплату твёрдого топлива
		_n_fact_payment numeric(10, 2); -- фактические расходы на оплату жку
		_n_last_ghku uuid; -- последний период жку тт
		
		_n_prev_rest_volume numeric; -- предыдущий остаток тт
		_n_prev_fact_payment NUMERIC(10, 2); -- предыдущие фактические расходы на жку
		_n_prev_annual_volume_sf NUMERIC; -- предыдущий приобретённый объём твёрдого топлива
		
		SN1 NUMERIC; -- социальная норма 1
		SN2 NUMERIC; -- социальная норма 2
		rec_tt record; -- итерация для расчёта тт
		_n_subsidy_tt numeric(10, 2); -- расчитанная субсидия тт
		_n_subsidy_main_tt numeric(10, 2); -- единовременная выплата за тт
		_n_coeff_tt numeric(10, 2); -- коэффициент для расчёта тт
		_end_temp_tt date; -- временная переменная для даты окончания по тт
		_end_tt date; -- дата окончания единовременной выплаты по тт

		--+++++++++++++++++++++++++--
		--         протокол        --
		--+++++++++++++++++++++++++--
		_br CHARACTER VARYING := chr(10); -- перенос на новую строку
		_max_length integer := 80; -- максимальная длина строки
		_с_divider CHARACTER VARYING := _br || lpad('', _max_length, '-') || _br; -- разделитель
		_с_case_number CHARACTER VARYING; -- номер дела
		_date_recalculation date; -- дата расчёта
		_с_declarant CHARACTER VARYING; -- заявитель
		_date_calculation date; -- дата заявления(обращения)
		_с_address CHARACTER VARYING; -- адрес жилого помещения
		_с_housing_stock_type CHARACTER VARYING; -- жилищный фонд
		_c_ownership_type CHARACTER VARYING; -- вид дома
		_c_capital_repair CHARACTER VARYING; -- взносы на кап. ремонт
		_f_calculation_type integer; -- тип расчёта
		_c_recalculation_reason_alias CHARACTER VARYING; -- причина перерасчёта
		_c_balance_holder CHARACTER VARYING; -- балансодержатель(управляющие компании)
		
		_protocol CHARACTER VARYING; -- протокол
		_c_header CHARACTER VARYING; -- заголовок
BEGIN
	-- select calculation.subsidy('25ea87da-30c1-4b4d-8914-95117023056b', '01.01.2019'::date, '30.06.2019'::date, '25ea87da-30c1-4b4d-8914-95117023056b');
	-- delete from subsidy.cd_calculation_periods where f_calculation = '25ea87da-30c1-4b4d-8914-95117023056b'
	--======================================================================--
	-- 				УДАЛЯЕМ ПРЕДЫДУЩИЕ РАССЧИТАННЫЕ ПЕРИОДЫ                 --
	--======================================================================--
	DELETE FROM subsidy.cd_calculation_periods
	WHERE f_calculation = _calc;
	
	--======================================================================--
	-- 							ОБЩИЕ ПЕРЕМЕННЫЕ                            --
	--======================================================================--
	SELECT r.f_case, 
	       r.b_enabled, 
	       r.b_sample_recaclulated,
	       t.c_alias, 
	       cd.n_day, 
	       d.f_district, 
	       d.f_settlement, 
	       m.n_percent,
	       cb.c_number,
	       r.d_recalculation,
	       p.c_surname || ' ' || p.c_first_name || ' ' || COALESCE(c_patronymic, ''),
	       r.d_date,
	       d.c_address,
	       hst.c_name,
	       hot.c_name,
	       CASE b_capital_repair 
	       		WHEN TRUE THEN 'Да'
	       		ELSE 'Нет'
	       END,
	       r.f_type,
	       rr.c_alias
	INTO _case, 
	     _b_enabled, 
	     _b_sampled_recalculated,
	     _c_subsidy_type, 
	     _n_last_calc_day, 
	     _f_district, 
	     _f_settlement, 
	     _n_maximum_share_cost,
	     _с_case_number,
	     _date_recalculation,
	     _с_declarant,
	     _date_calculation,
	     _с_address,
	     _с_housing_stock_type,
	     _c_ownership_type,
	     _c_capital_repair,
	     _f_calculation_type,
	     _c_recalculation_reason_alias
	FROM subsidy.cd_calculations AS r
	INNER JOIN subsidy.cd_cases AS d ON r.f_case = d.id
	INNER JOIN common.cd_case_base AS cb ON d.id = cb.id
	INNER JOIN public.cd_persons AS p ON cb.f_person = p.id
	INNER JOIN subsidy.cs_subsidy_types AS t ON r.f_subsidy_type = t.id
	INNER JOIN subsidy.cs_last_calculation_day AS cd ON r.f_last_calculation_day = cd.id
	INNER JOIN subsidy.cs_housing_stock_types AS hst ON r.f_housing_stock_type = hst.id
	INNER JOIN subsidy.cs_house_ownership_types AS hot ON r.f_ownership_type = hot.id
	LEFT JOIN subsidy.cs_maximum_share_costs AS m ON d.f_maximum_share_cost = m.id
	LEFT JOIN subsidy.cs_recalculation_reasons AS rr ON r.f_recalculation_reason = rr.id 
	WHERE r.id = _calc;

	--======================================================================--
	--                           БАЛАНСОДЕРЖАТЕЛИ                           --
	--======================================================================--
	SELECT COALESCE(string_agg(COALESCE(m.c_name, '') || '; ' || 'лиц. счёт №: ' || COALESCE(cm.c_account, ''), _br), '')
	INTO _c_balance_holder
	FROM subsidy.cd_cases_management_companies AS cm 
	INNER JOIN subsidy.cd_cases AS d ON cm.f_case = d.id
	INNER JOIN subsidy.cs_management_companies AS m ON cm.f_management_company = m.id
	WHERE cm.f_case = _case;
	
	--======================================================================--
	--                               РАСЧЁТЫ                                --
	--======================================================================--
	DROP TABLE IF EXISTS _calculations;
	CREATE TEMP TABLE _calculations
	(
		_id uuid, -- идентификатор
		_n_number integer, -- номер
		_d_date date, -- дата заявления
		_n_count_location integer, -- кол-во пмж
		_n_count_place_stay integer, -- кол-во пмп
		_n_count_temp_absent integer, -- кол-во временно отсутствующих
		_n_all integer, -- общее кол-во проживающих
		_f_dwelling_user integer, -- тип пользования жилого помещения
		_f_housing_stock_type integer, -- вид жил.фонда
		_f_ownership_type integer, -- вид домовладения
		_f_house_type integer, -- тип дома
		_b_capital_repair boolean, -- кап.ремонт
		_n_area numeric(10, 2), -- площадь жилого помещения
		_n_annual_volume_solid_fuel numeric(10, 2), -- годовой объём твёрдого топлива
		_n_months_solid_fuel numeric(10, 2), -- кол-во месяцев по нормативу
		_n_fact_payment_year_solid_fuel numeric(10, 2), -- размер фактических расходов на оплату ТТ с учётом льгот
		_n_fact_payment_month_solid_fuel numeric(10, 2), -- размер среднемесячных расходов на оплату ТТ с учётом льгот
		_n_rest_volume_solid_fuel numeric(10, 2), -- неиспользованный остаток ТТ
		_n_normative_costs_solid_fuel numeric(10, 2) -- нормативные расходы
	) ON COMMIT DROP;
	DELETE FROM _calculations;

	INSERT INTO _calculations(_id, 
							  _n_number,
							  _d_date, 
							  _n_count_location, 
							  _n_count_place_stay, 
							  _n_count_temp_absent, 
							  _n_all,
							  _f_dwelling_user,
							  _f_housing_stock_type,
							  _f_ownership_type,
							  _f_house_type,
							  _b_capital_repair,
							  _n_area,
							  _n_annual_volume_solid_fuel,
							  _n_months_solid_fuel,
							  _n_fact_payment_year_solid_fuel,
							  _n_fact_payment_month_solid_fuel,
							  _n_rest_volume_solid_fuel,
							  _n_normative_costs_solid_fuel)
	SELECT r.id, 
		   r.n_number,
		   r.d_date, 
		   r.n_count_location, 
		   r.n_count_place_stay, 
		   r.n_count_temp_absent, 
		   r.n_all,
		   r.f_dwelling_user,
   		   r.f_housing_stock_type,
		   r.f_ownership_type,
		   r.f_house_type,
		   r.b_capital_repair,
		   r.n_area,
		   r.n_annual_volume_solid_fuel,
		   r.n_months_solid_fuel,
		   r.n_fact_payment_year_sf,
		   r.n_fact_payment_month_sf,
		   r.n_rest_volume_sf,
		   r.n_normative_costs
	FROM subsidy.cd_calculations AS r
	WHERE r.id IN (SELECT unnest(string_to_array(_calc_array, ','))::uuid);

	--======================================================================--
	-- 							ОСНОВНАЯ ЛОГИКА                             --
	--======================================================================--
	FOR rec IN SELECT * FROM _calculations LOOP	
		--======================================================================--
		-- 								СОСТАВ СЕМЬИ                            --
		--======================================================================--
		DROP TABLE IF EXISTS _people;
		CREATE TEMP TABLE _people
		(
			_row_count integer, -- номер строки
			_id uuid, -- идентификатор
			_person integer, -- фл
			_registration_alias CHARACTER VARYING, -- тип регистрации
			_sdg_alias CHARACTER VARYING, -- сдг
			_family_rel CHARACTER VARYING, -- родственное отношение
			_income numeric(10, 2), -- доход
			_farm_income numeric(10, 2), -- доход от лпх
			_owner_share numeric, -- доля собственности
			_family integer, -- семья
			_calculation uuid -- расчёт
		) ON COMMIT DROP;
		DELETE FROM _people;
		
		INSERT INTO _people(_row_count,
							_id, 
							_person, 
							_registration_alias, 
							_sdg_alias, 
							_family_rel,
							_income, 
							_farm_income,
							_owner_share,
							_family,
							_calculation)
		SELECT row_number() over (ORDER BY rel_alias),
		       t.id, 
		       t.person, 
		       t.reg_type_alias,
		       t.sdg_alias, 
		       t.rel_name, 
		       t.income,
		       t.farm_income, 
		       t.owner_share, 
		       t.family,
		       t.calc_id
		FROM(SELECT p.id AS id, 
			    	p.f_person AS person, 
				    t.c_alias AS reg_type_alias, 
				    s.c_alias AS sdg_alias,
		            rel.c_alias AS rel_alias, 
		            rel.c_name AS rel_name,
		            coalesce(sum(i.n_value / i.n_months), 0) AS income,
		            coalesce(sum(f."Value"), 0) AS farm_income,
			    	p.n_numerator::numeric / p.n_denominator::numeric AS owner_share,
		            p.n_family AS family,
		            p.f_calculation AS calc_id
			FROM subsidy.cd_calculation_persons AS p
			INNER JOIN subsidy.cs_socio_demographic_groups AS s ON p.f_sdg = s.id
		 	INNER JOIN public.cs_registration_types AS t ON p.f_registration_type = t.id
			LEFT JOIN subsidy.cs_family_relations AS rel ON p.f_family_relation = rel.id
			LEFT JOIN subsidy.cd_person_incomes AS i ON p.id = i.f_calculation_person
			LEFT JOIN subsidy.cd_farm_counts AS f ON p.id = f.f_calculation_person
			WHERE p.f_calculation = rec._id
			GROUP BY p.id, p.f_person, t.c_alias, s.c_alias, rel.c_alias, rel.c_name
			ORDER BY rel.c_alias) AS t;
		
		-- кол-во зарегистрированных пмж
		_count_location := (SELECT count(*) 
						    FROM _people
						    WHERE _registration_alias = 'location');
		-- кол-во зарегистрированных пмп
		_count_place_stay := (SELECT count(*) 
						      FROM _people
						      WHERE _registration_alias = 'place_stay');
		-- кол-во зарегистрированных по другому адресу
		_count_other_address := (SELECT count(*) 
								 FROM _people
								 WHERE _registration_alias = 'other_address');
		-- кол-во временно отсутствующих
		_count_temp_absent := (SELECT count(*) 
						       FROM _people
						       WHERE _registration_alias = 'temp_absent');
		-- кол-во членов семьи
		_count_family_members := (SELECT count(*)
								  FROM _people);
		 -- кол-во трудоспособных							 
		_count_employees := (SELECT count(*)
							 FROM _people 
							 WHERE _sdg_alias = 'employable');
		-- кол-во пенсионеров						
		_count_pensioners := (SELECT count(*)
							  FROM _people
						 	  WHERE _sdg_alias = 'pensioner');
		-- кол-во детей						  
		_count_children := (SELECT count(*)
							FROM _people
							WHERE _sdg_alias = 'child'); 							 
		-- среднемесячный совокупный доход семьи в расчётном периоде
		SELECT coalesce(((sum(_income) + sum(_farm_income)) * _count_location::numeric) 
							/ _count_family_members::numeric, 0)
		INTO _average_month_income
		FROM _people
		WHERE _calculation = rec._id;
		-- среднедушевой доход семьи в расчётном периоде
		_percapita_income := _average_month_income / _count_location::numeric;

		-- социальная норма площади жилого помещения
		IF rec._n_count_location = _count_location THEN
			IF rec._n_count_location >= 3 THEN
				_n_republic_area := (SELECT (n_three * _count_location) + n_additional
								     FROM subsidy.cs_republic_area_standarts
								     ORDER BY d_begin DESC
								     LIMIT 1);
			ELSIF rec._n_count_location = 2 THEN
				_n_republic_area := (SELECT (n_two * _count_location) + n_additional
								     FROM subsidy.cs_republic_area_standarts
								     ORDER BY d_begin DESC
								     LIMIT 1);
			ELSIF rec._n_count_location = 1 THEN
				_n_republic_area := (SELECT n_one 
								     FROM subsidy.cs_republic_area_standarts
								     ORDER BY d_begin DESC
								     LIMIT 1);			
			END IF;
		ELSIF rec._n_count_location > _count_location THEN
			IF rec._n_count_location = 2 THEN
				_n_republic_area := (SELECT ((n_two * rec._n_count_location + n_additional) 
												/ rec._n_count_location::decimal) * (_count_location)::decimal
								     FROM subsidy.cs_republic_area_standarts 
								     ORDER BY d_begin DESC
								     LIMIT 1);
			ELSIF rec._n_count_location >= 3 THEN
				_n_republic_area := (SELECT ((n_three * rec._n_count_location + n_additional) 
												/ rec._n_count_location::decimal) * (_count_location)::decimal
								     FROM subsidy.cs_republic_area_standarts 
								     ORDER BY d_begin DESC
								     LIMIT 1);			
			END IF;
		END IF;

		--======================================================================--
		--   					 	   	ПЕРИОДЫ     						    --
		--======================================================================--
		DROP TABLE IF EXISTS _periods;
		CREATE TEMP TABLE _periods
		(
			_id uuid NOT NULL DEFAULT public.new_guid(),
			_n_family_living_minimum numeric, -- прожиточный минимум семьи
			_n_one numeric(10, 2), -- ссжку на 1 из 1
			_n_two numeric(10, 2), -- ссжку на 1 из 2
			_n_three numeric(10, 2), -- ссжку на 1 из 3
			_d_begin date, -- дата начала (минимальная)
			_d_end date, -- дата окончания (максимальная)
			_per_begin date, -- дата начала (период)
			_per_end date, -- дата окончания (период)
			_lm_begin date, -- дата начала (прожиточный минимум)
			_lm_end date, -- дата окончания (прожиточный минимум)
			_ss_begin date, -- дата начала (ссжку)
			_ss_end date, -- дата окончания (ссжку)
			_number_of_days integer, -- кол-во дней в месяце
			_date_diff integer, -- разница в днях
			_ghku_default numeric(10, 2), -- жку за предыдущий месяц
			_ghku_sampled_rec numeric(10, 2), -- жку за все месяцы расчитываемого периода
			_n_ssghku numeric(10, 2), -- расчитанный ссжку
			_c_ssghku_formula CHARACTER VARYING, -- формула расчёта ссжку
			_adjustment_coeff numeric(10, 4) DEFAULT 0, -- поправочный коэффициент
			_adjustment_coeff_formula CHARACTER VARYING DEFAULT '', -- формула поправочного коэффициента
			_n_subsidy numeric(10, 2), -- размер субсидии
			_subsidy_formula CHARACTER VARYING, -- формула расчёта субсидии
			_n_payout numeric(10, 2), -- сумма на выплату
			_n_prev_payout numeric(10, 2), -- сумма на выплату в предыдущем расчёте
--			_n_subsidy_tt numeric(10, 2), -- размер субсидии на твёрдое топливо
			_n_subsidy_main_tt numeric(10, 2) -- единовременная выплата по тт
		) ON COMMIT DROP;
		DELETE FROM _periods;

		INSERT INTO _periods(_n_family_living_minimum,
							 _n_one,
							 _n_two,
							 _n_three,
							 _per_begin,
							 _per_end,
							 _lm_begin,
							 _lm_end,
							 _ss_begin, 
							 _ss_end,
							 _ghku_default, 
							 _ghku_sampled_rec,
							 _n_prev_payout)
		SELECT ((l.n_employable * _count_employees) 
		   		+ (l.n_pensioner * _count_pensioners)
		   	    + (l.n_child * _count_children)) / _count_family_members::decimal,
		   	    s.n_one,
		   	    s.n_two,
		   	    s.n_three,
			   p._d_begin,
			   p._d_end,
			   l.d_begin,
			   CASE 
			   	WHEN l.d_end < _begin THEN NULL 
			   	ELSE l.d_end 
			   END,
			   s.d_begin,
			   CASE 
			   	WHEN s.d_end < _begin 
			   	THEN NULL ELSE s.d_end 
			   END,
	   		   g.n_total,
	   		   gs.n_total,
	   		   COALESCE(prev_calc.n_payout, 0)
	   	FROM (SELECT (date_part('year', p::date) || '-' || date_part('month', p::date) || '-01')::date AS _d_begin,
			   (((date_part('year', p::date) || '-' || date_part('month', p::date) || '-01')::date
				+ '1 mons'::INTERVAL) - '1 day'::INTERVAL)::date AS _d_end
			  FROM generate_series(_begin, _end, '1 mons'::INTERVAL) AS p) AS p
			  LEFT JOIN LATERAL(SELECT n_employable, n_pensioner, n_child, d_begin, d_end
								FROM subsidy.cs_living_minimums
								WHERE (d_begin::date <= p._d_begin AND d_end IS NULL)
								  		OR (d_begin, d_end) OVERLAPS(p._d_begin, p._d_end)) AS l ON TRUE
			  LEFT JOIN LATERAL(SELECT id, n_one, n_two, n_three, d_begin::date, d_end::date
				  			    FROM subsidy.cs_standart_payment_living_communal_service_averages
				  			    WHERE f_district = _f_district 
				  			   		  AND (_f_settlement IS NULL OR f_settlement = _f_settlement) 
			    					  AND b_capital_repair = rec._b_capital_repair 
			    					  AND f_house_ownership_type = rec._f_ownership_type 
			    					  AND f_dwelling_user = rec._f_dwelling_user	
			    					  AND (rec._f_house_type IS NULL OR f_house_type = rec._f_house_type)
			    					  AND b_expired = FALSE 
			    					  AND b_copied = FALSE 
			    					  AND date_part('year', p._d_begin) * 100 + date_part('month', p._d_begin) >= date_part('year', d_begin) * 100 + date_part('month', d_begin) 
			      			    ORDER BY date_part('year', d_end) * 100 + date_part('month', d_end) DESC
			      			    LIMIT 1) AS s ON TRUE
			  LEFT JOIN LATERAL(SELECT *
				  				FROM subsidy.cd_cases_ghku
				  				WHERE f_case = _case
				  					  AND n_year * 100 + f_month = date_part('year', rec.d_date - '1 mons'::INTERVAL) * 100 + date_part('month', rec.d_date - '1 mons'::INTERVAL)
				  				ORDER BY b_last DESC
				  				LIMIT 1) AS g ON TRUE	
			  LEFT JOIN LATERAL(SELECT *
				  				FROM subsidy.cd_cases_ghku
				  				WHERE f_case = _case
				  	    			  AND n_year * 100 + f_month = date_part('year', p._d_begin) * 100 + date_part('month', p._d_end)
				  				ORDER BY b_last DESC
				  				LIMIT 1) AS gs ON TRUE
			  LEFT JOIN LATERAL(SELECT sum(per.n_payout) AS n_payout
			  				    FROM subsidy.cd_calculation_periods AS per
			  				    INNER JOIN subsidy.cd_calculations AS r ON per.f_calculation = r.id
			  				    WHERE r.f_case = _case
			  				    	  AND per.f_calculation != rec._id
			  				    	  AND per.b_payout = TRUE
			  				    	  AND r.b_enabled = FALSE
			  				    	  AND date_part('year', per.d_begin) * 100 + date_part('month', per.d_begin) 
			  				    	  		= date_part('year', p._d_begin) * 100 + date_part('month', p._d_begin)) AS prev_calc ON TRUE;
-- 		ORDER BY b, e;	   
		--======================================================================--
		--                          ОПРЕДЕЛЯЕМ ДАТЫ                             --
		--======================================================================--
		UPDATE _periods
		SET _d_begin = GREATEST(_lm_begin, _ss_begin, _per_begin),
		    _d_end = LEAST(_lm_end, _ss_end, _per_end),
		    _number_of_days = date_part('days', date_trunc('month', GREATEST(_lm_begin, _ss_begin, _per_begin)) + '1 month'::INTERVAL - '1 day'::INTERVAL),
		    _date_diff = date_part('days', LEAST(_lm_end, _ss_end, _per_end)) - date_part('days', GREATEST(_lm_begin, _ss_begin, _per_begin)) + 1;
		
		
		--======================================================================--
		--                            РАСЧЁТ ССЖКУ                              --
		--======================================================================--
		IF rec._n_count_location = _count_location THEN
			IF rec._n_count_location >= 3 THEN
				UPDATE _periods
				SET _n_ssghku = round(_n_three, 2) * _count_location,
				    _c_ssghku_formula = round(_n_three, 2)::CHARACTER VARYING || ' * ' 
			   						     || _count_location::CHARACTER VARYING || ' = ' 
			   					         || (round(_n_three, 2) * _count_location)::CHARACTER VARYING;
			ELSIF rec._n_count_location = 2 THEN
				UPDATE _periods
				SET _n_ssghku = round(_n_two, 2) * _count_location,
					_c_ssghku_formula = round(_n_two, 2)::CHARACTER VARYING || ' * ' 
			   						   	 || _count_location::CHARACTER VARYING || ' = ' 
			   					         || (round(_n_two, 2) * _count_location)::CHARACTER VARYING;
			ELSE
				UPDATE _periods
				SET _n_ssghku = round(_n_one, 2), 
					_c_ssghku_formula = round(_n_one, 2)::CHARACTER VARYING;				
			END IF;
		ELSIF rec._n_count_location > _count_location THEN
			IF (rec._n_count_location * _count_location) != 0 THEN
				IF rec._n_count_location >= 3 THEN
					UPDATE _periods
					SET _n_ssghku = ((round(_n_three, 2) * rec._n_count_location) / rec._n_count_location::decimal) 
										* _count_location, 
						_c_ssghku_formula = round(_n_three, 2)::CHARACTER VARYING || ' * ' 
				   						   	 || rec._n_count_location::CHARACTER VARYING || ' / ' 
				   					         || rec._n_count_location::CHARACTER VARYING || ' * ' 
				   					         || _count_location::CHARACTER VARYING || ' = '
				   				             || (((round(_n_three, 2) * rec._n_count_location) / rec._n_count_location::decimal) 
											     * _count_location)::CHARACTER VARYING;
				ELSIF rec._n_count_location = 2 THEN
					UPDATE _periods
					SET _n_ssghku = ((round(_n_two, 2) * rec._n_count_location) / rec._n_count_location::decimal)
										* _count_location,
						_c_ssghku_formula = round(_n_two, 2)::CHARACTER VARYING || ' * ' 
										     || rec._n_count_location::CHARACTER VARYING || ' / '
										     || rec._n_count_location::CHARACTER VARYING || ' * '
										     || _count_location::CHARACTER VARYING || ' = '
										     || (((round(_n_two, 2) * rec._n_count_location) / rec._n_count_location::decimal)
											     * _count_location)::CHARACTER VARYING;
				END IF;
			END IF;
		END IF;
		
		--======================================================================--
		--                       ПОПРАВОЧНЫЙ КОЭФФИЦИЕНТ                        --
		--======================================================================--
		UPDATE _periods
		SET _adjustment_coeff = case when _n_family_living_minimum != 0 THEN round((_percapita_income / _n_family_living_minimum), 4) ELSE 0 END,
			_adjustment_coeff_formula = _percapita_income::CHARACTER VARYING || ' / ' || round(_n_family_living_minimum, 2)::CHARACTER VARYING
											|| ' = ' || round((_percapita_income / _n_family_living_minimum), 4)::CHARACTER VARYING;
		--======================================================================--
		--                            РАЗМЕР СУБСИДИИ                           --
		--======================================================================--
		UPDATE _periods
		SET _n_subsidy = case when _percapita_income >= _n_family_living_minimum then round(_n_ssghku, 2) - round((_n_maximum_share_cost / 100), 2) * _average_month_income
				      else round(_n_ssghku, 2) - round((_n_maximum_share_cost / 100), 2) * (_average_month_income * round(_adjustment_coeff, 4))
				 end,
		    _subsidy_formula = case when _percapita_income >= _n_family_living_minimum then 'по первому основанию: (' || round(_n_ssghku, 2)::CHARACTER VARYING || ' - ' || _average_month_income::CHARACTER VARYING
								   || ' * ' || round((_n_maximum_share_cost / 100), 2)::CHARACTER VARYING || ')' 
								   || ' / ' || _number_of_days::CHARACTER VARYING || ' * ' || _date_diff::CHARACTER VARYING
					    else 'по второму основанию: (' || round(_n_ssghku, 2)::CHARACTER VARYING || ' - '
						 || _average_month_income::CHARACTER VARYING || ' * ' || round((_n_maximum_share_cost / 100), 2)::CHARACTER VARYING
						 || ' * ' || round(_adjustment_coeff, 4)::CHARACTER VARYING || ')'
						 || ' / ' || _number_of_days::CHARACTER VARYING || ' * ' || _date_diff::CHARACTER VARYING
				       end;

		--======================================================================--
		--            ЕСЛИ РАЗМЕР СУБСИДИИ ПРЕВЫШАЕТ ПЛАТУ ЗА ЖКУ               --
		--======================================================================--
		IF _b_sampled_recalculated = FALSE THEN
			UPDATE _periods
			SET _n_subsidy = CASE 
						   		WHEN _ghku_default < _n_subsidy THEN _ghku_default
						   		ELSE _n_subsidy
						     END;
		ELSE
			UPDATE _periods
			SET _n_subsidy = CASE 
						   		WHEN _ghku_sampled_rec < _n_subsidy THEN _ghku_sampled_rec
						   		ELSE _n_subsidy
						     END;
		END IF;
		
		--======================================================================--
		-- 							СУММА НА ВЫПЛАТУ                            --
		--======================================================================--
		UPDATE _periods
		SET _n_payout = CASE  
							WHEN _n_prev_payout = 0 AND _n_subsidy > 0 THEN _n_subsidy
							WHEN _n_prev_payout = 0 AND _n_subsidy <= 0 THEN 0
							WHEN _n_prev_payout != 0 AND _n_subsidy > 0 THEN _n_subsidy - _n_prev_payout
							WHEN _n_prev_payout != 0 AND _n_subsidy <= 0 THEN 0 - _n_prev_payout
						END;


		IF _c_subsidy_type = 'tt' THEN
			--======================================================================--
			--                             ТВЁРДОЕ ТОПЛИВО                          --
			--======================================================================--
			SELECT sum(_owner_share)
			INTO _n_owners_share -- общая доля собственности
			FROM _people;
		
			SELECT n.n_year,
				   p.n_scope,
				   p.n_sum,
				   p.n_discount,
				   COALESCE(p.n_sum, 0) - COALESCE(p.n_discount, 0)
			INTO _n_normative_year,
				 _n_volume,
				 _n_fuel_payment,
				 _n_fuel_discount,
				 _n_fact_payment_year
			FROM subsidy.cd_case AS d 
			LEFT JOIN subsidy.cd_cases_ghku AS g ON d.id = g.f_case
			LEFT JOIN subsidy.cd_cases_ghku_periods AS p ON p.f_case_ghku = g.id
			LEFT JOIN subsidy.cs_ghku_types AS t ON p.f_type = t.id
			LEFT JOIN subsidy.cs_solid_fuel_normatives AS n ON t.id = n.f_type
			WHERE d.id = _case
				  AND date_part('year', rec._d_date) * 100 + date_part('month', rec._d_date) 
				  		= g.n_year * 100 + g.f_month
				  AND t.c_code LIKE '37%'
			ORDER BY g.b_last DESC
			LIMIT 1;
	
			SELECT coalesce(r.n_rest_volume_sf, 0), 
				   coalesce(r.n_fact_payment_year_sf, 0), 
				   coalesce(r.n_annual_volume_solid_fuel, 0)
			INTO _n_prev_rest_volume, 
			     _n_prev_fact_payment,
			     _n_prev_annual_volume_sf
			FROM subsidy.cd_calculations AS r 
			INNER JOIN subsidy.cs_subsidy_types AS t ON r.f_subsidy_type = t.id
			WHERE r.f_case = _case
				  AND r.n_number < rec._n_number
				  AND t.c_alias = 'tt'
			ORDER BY r.n_number DESC
			LIMIT 1;
			
			-- объем твёрдого топлива
			_n_volume := _n_volume + _n_prev_rest_volume;
		
			-- фактические расходы на оплату жку
			SELECT CASE t.b_owner 
						WHEN TRUE THEN ((p.n_sum::NUMERIC(10, 2) - p.n_discount::NUMERIC(10, 2)) * _n_owners_share)::NUMERIC(10, 2)
						WHEN FALSE THEN (((p.n_sum::NUMERIC(10, 2) - p.n_discount::NUMERIC(10, 2)) / (rec._n_count_location + rec._n_count_place_stay)::numeric(10, 2))
											* (_count_location + _count_place_stay))::NUMERIC(10, 2)
						ELSE g.n_total - g.n_discount
					END,
					g.id
			INTO _n_fact_payment,
				_n_last_ghku
			FROM subsidy.cd_cases_ghku AS g
			LEFT JOIN subsidy.cd_cases_ghku_periods AS p ON g.id = p.f_case_ghku
			LEFT JOIN subsidy.cs_ghku_types AS t ON p.f_type = t.id
			WHERE g.f_case = _case 
				  AND (t.c_code NOT LIKE '37%' AND t.c_code NOT LIKE '00%')
				  AND date_part('year', (_date_calculation - '1 mons'::INTERVAL)::date) * 100 + date_part('month', (_date_calculation - '1 mons'::INTERVAL)::date) 
				  		= g.n_year * 100 + g.f_month
			GROUP BY g.id, g.n_year, g.f_month, g.b_last	  		
			ORDER BY g.b_last DESC
			LIMIT 1;
			
			-- нормативные расходы
			SELECT sum(COALESCE(p.n_normative, 0) * COALESCE(p.n_tarif, 0) * COALESCE(_count_location, 0))
			INTO _n_normative_cost
			FROM subsidy.cd_cases_ghku_periods AS p
			INNER JOIN subsidy.cs_ghku_types AS t ON p.f_type = t.id
			WHERE p.f_case_ghku = _n_last_ghku
				  AND (t.c_code LIKE '30%' OR t.c_code LIKE '31%' OR
				 	   t.c_code LIKE '33%' OR t.c_code LIKE '34%' OR
				 	   t.c_code LIKE '35%' OR t.c_code LIKE '39%');
				 	  
			-- годовой объём твёрдого топлива по нормативу
			_n_annual_volume := LEAST(rec._n_area, _n_republic_area) * _n_normative_year;
			
			-- кол-во месяцев по нормативу
			IF _n_annual_volume != 0 THEN
				_n_months := (_n_volume * 12) / _n_annual_volume;
			END IF;
			
			-- размер фактических расходов на оплату ТТ
			IF _n_prev_annual_volume_sf != 0 THEN
				_n_fact_payment_year := _n_fact_payment_year + (_n_prev_fact_payment / _n_prev_annual_volume_sf::NUMERIC) * _n_prev_rest_volume;
			END IF;
		
			IF _n_months != 0 THEN 
				-- размер среднемесячных расходов на оплату ТТ
				_n_fact_payment_month := _n_fact_payment_year / _n_months;
				
				-- неиспользованный остаток ТТ
				_n_rest_volume := _n_volume - (_n_volume / _n_months) * 6;
			ELSE
				-- размер среднемесячных расходов на оплату ТТ
				_n_fact_payment_month := 0;
				
				-- неиспользованный остаток ТТ
				_n_rest_volume := _n_volume;
			END IF;
			
			-- кол-во целых месяцев
			_n_sol_months := trunc(_n_months);
		
			-- кол-во дней в последнем месяце
			_n_days_in_month := date_part('days', date_trunc('month', (rec._d_date 
											+ (_n_sol_months::CHARACTER VARYING || ' mons')::INTERVAL)::date) 
											+ '1 month'::INTERVAL - '1 day'::INTERVAL);
			
			SN1 := 0;
			SN2 := 0;
										
			IF _n_fact_payment > _n_normative_cost THEN
				SN1 := _n_normative_cost + _n_fact_payment_month;
			ELSE 
			    SN2 := _n_fact_payment + _n_fact_payment_month;
			END IF;
		
			--======================================================================--
			--                         РАСЧЁТ СУБСИДИИ ПО ТТ                        --
			--======================================================================--
			FOR rec_tt IN SELECT * FROM _periods LOOP
				_n_subsidy_tt := 0;
				_n_subsidy_main_tt := 0;
				_n_coeff_tt := 0;
			
				IF (rec_tt._n_subsidy < SN1) OR (rec_tt._n_subsidy < SN2) THEN
					IF rec_tt._n_subsidy < SN1 AND SN2 = 0 THEN
						_n_subsidy_tt := (_n_normative_cost / SN1) * rec_tt._n_subsidy;
						_n_coeff_tt := (_n_fact_payment_month / SN1) * rec_tt._n_subsidy;
						IF _n_monts > 6 THEN
							_n_subsidy_main_tt := _n_coeff_tt * 6;
						ELSE 
							_n_subsidy_main_tt := (_n_coeff_tt * 6 / (6 * _n_sol_months)::NUMERIC) 
													+ ((_n_coeff_tt * 6) / 6) / (_n_days_in_month * trunc(_n_days_in_month * (_n_months - floor(_n_months))));
						END IF;
					END IF;
					
					IF rec_tt.n_subsidy < SN2 AND SN1 = 0 THEN
						_n_subsidy_tt := (_n_fact_payment / SN2) * rec_tt._n_subsidy;
						_n_coeff_tt := (_n_fact_payment_month / SN2) * rec_tt._n_subsidy;
						IF _n_months > 6 THEN 
							_n_subsidy_main_tt := _n_coeff_tt * 6;
						ELSE 
							_n_subsidy_main_tt := ((_n_coeff_tt * 6) / (6 * _n_sol_months)::NUMERIC) 
													+ ((_n_coeff_tt * 6) / 6) / (_n_days_in_month * trunc(_n_days_in_month * (_n_months - floor(_n_months))));
						END IF;
					END IF;
				ELSE 
					IF (rec_tt._n_subsidy > SN1 OR rec_tt._n_subsidy > SN2)
						AND _n_fact_payment > rec_tt._n_subsidy THEN
						_n_coeff_tt := _n_fact_payment_month * 6;
						IF _n_months > 6 THEN
							_n_subsidy_main_tt := _n_coeff_tt;
						ELSE 
							_n_subsidy_main_tt := (_n_coeff_tt / (6 * _n_sol_months)::NUMERIC) 
													+ (_n_coeff_tt / 6::NUMERIC) / (_n_days_in_month * trunc(_n_days_in_month * (_n_months - floor(_n_months))));
						END IF;
					END IF;	
					
					IF (rec_tt._n_subsidy > SN2 OR rec_tt._n_subsidy > SN1) 
						AND _n_fact_payment < rec_tt._n_subsidy THEN
						_n_coeff_tt := _n_fact_payment_month * 6;
						IF _n_months > 6 THEN
							_n_subsidy_main_tt := _n_coeff_tt;
						ELSE 
							_n_subsidy_main_tt := (_n_coeff_tt / (6 * _n_sol_months)::NUMERIC) 
													+ (_n_coeff_tt / 6::NUMERIC) / (_n_days_in_month * trunc(_n_days_in_month * (_n_months - floor(_n_months))));
						END IF;
					END IF;
				
					IF (rec_tt._n_subsidy > SN2 OR rec_tt._n_subsidy > SN1)
						AND rec_tt._n_subsidy > (_n_fact_payment + _n_fact_payment_month) THEN
						_n_subsidy_tt := _n_fact_payment;
					END IF;
				
					IF rec_tt._n_subsidy > SN1 
						AND rec_tt._n_subsidy < (_n_fact_payment + _n_fact_payment_month) THEN
						_n_subsidy_tt := rec_tt._n_subsidy - _n_fact_payment_month;
					END IF;
					
					IF _n_fact_payment = 0 
						AND (rec_tt._n_subsidy > SN1 OR rec_tt._n_subsidy > SN2) THEN
						_n_subsidy_tt := 0;
						_n_subsidy_main_tt := _n_fact_payment_month * 6;
					END IF;
				END IF;
			
				UPDATE _periods AS p
				SET p._n_subsidy = COALESCE(_n_subsidy_tt, 0),
					p._n_payout = CASE 
									 WHEN COALESCE(_n_subsidy_tt, 0) < 0 THEN 0
									 ELSE COALESCE(_n_subsidy_tt, 0)
	 							END,
					 p._n_subsidy_main_tt = COALESCE(_n_subsidy_main_tt, 0)
				WHERE p.id = rec_tt._id; 
			END LOOP;
										
	   		--======================================================================--
			--             РАЗМЕР СУБСИДИИ И СУММЫ НА ВЫПЛАТУ В ПРОПОРЦИЯХ          -- 
			--======================================================================--
			UPDATE _periods
			SET _n_subsidy = (_n_subsidy / _number_of_days::decimal) * _date_diff,
				_n_payout = (_n_payout / _number_of_days::decimal) * _date_diff,
				_n_subsidy_main_tt = (_n_subsidy_main_tt / _number_of_days::decimal) * _date_diff;
			
			--======================================================================--
			--                     ЕДИНОВРЕМЕННАЯ ВЫПЛАТА ПО ТТ                     --
			--======================================================================--
			IF _b_enabled = FALSE THEN
				_end_tt := _end;
				IF _n_months < 6 THEN
					_end_temp_tt := (_begin + ((_n_sol_months)::CHARACTER VARYING || ' mons')::INTERVAL)::date;
					_end_tt := (lpad(trunc(_n_days_in_month * (_n_months - floor(_n_months)) + 1)::CHARACTER VARYING, 2, '0') 
																|| '.' || lpad(date_part('months', _end_temp_tt)::CHARACTER VARYING, 2, '0') 
															    || '.' || date_part('year', _end_temp_tt))::date;
				END IF;
				
				INSERT INTO subsidy.cd_calculation_periods(f_calculation, d_begin, d_end, n_subsidy, n_payout, b_solid_fuel)
				SELECT _calc, _begin, _end_tt, sum(p._n_subsidy_main_tt), sum(p._n_subsidy_main_tt), TRUE
				FROM _periods;
			END IF;
		
			UPDATE subsidy.cd_calculations
			SET n_annual_volume_solid_fuel = COALESCE(_n_volume, 0),
				n_months_solid_fuel = COALESCE(_n_months, 0),
				n_fact_payment_year_sf = COALESCE(_n_fact_payment_year, 0),
				n_fact_payment_month_sf = COALESCE(_n_fact_payment_month, 0),
				n_rest_volume_sf = COALESCE(_n_rest_volume, 0),
				n_normative_costs = COALESCE(_n_normative_cost, 0)
			WHERE id = _calc;
		
		ELSE 
	   		--======================================================================--
			--             РАЗМЕР СУБСИДИИ И СУММЫ НА ВЫПЛАТУ В ПРОПОРЦИЯХ          -- 
			--======================================================================--
			UPDATE _periods
			SET _n_subsidy = (_n_subsidy / _number_of_days::decimal) * _date_diff,
				_n_payout = (_n_payout / _number_of_days::decimal) * _date_diff;
		
		END IF;
		
		--======================================================================--
		--                 ЗАПИСЫВАЕМ РЕЗУЛЬТАТЫ РАСЧЁТА                        -- 
		--======================================================================--
		INSERT INTO subsidy.cd_calculation_periods(f_calculation, d_begin, d_end, 
												   n_subsidy, n_payout,
												   n_family_living_minimum, 
												   n_adjustment_coeff, c_adjustment_coeff_formula,
												   n_ssghku, c_ssghku_formula,
												   n_republic_area, n_maximum_share_cost)
	    SELECT _calc, p._d_begin, p._d_end,
	    	   p._n_subsidy, p._n_payout,
	    	   p._n_family_living_minimum,
	    	   p._adjustment_coeff, p._adjustment_coeff_formula,
	    	   p._n_ssghku, p._c_ssghku_formula,
	    	   _n_republic_area, _n_maximum_share_cost
	    FROM _periods AS p;
	   

	END LOOP;

	--======================================================================--
	-- 	       		             ПРОТОКОЛ                                   --
	--======================================================================--
	IF _b_enabled = TRUE THEN -- массовый перерасчёт
		_c_header := 'ПРОТОКОЛ ПЕРЕРАСЧЁТА СУБСИДИИ НА ОПЛАТУ ЖКУ И КОММУНАЛЬНЫХ УСЛУГ' || _br
					 || CASE _f_calculation_type 
							WHEN 3 THEN 'В СВЯЗИ С ИЗМЕНЕНИЕМ СТАНДАРТА СТОИМОСТИ ЖКУ' || _br
							WHEN 4 THEN 'В СВЯЗИ С ИЗМЕНЕНИЕМ ПРОЖИТОЧНОГО МИНИМУМА' || _br
							WHEN 5 THEN 'В СВЯЗИ С ИЗМЕНЕНИЕМ СТАНДАРТА СТОИМОСТИ ЖКУ И ПРОЖИТОЧНОГО МИНИМУМА' || _br
							ELSE ''
						END;
	ELSIF _b_sampled_recalculated = TRUE THEN -- выборочный перерасчёт
		_c_header := 'ПРОТОКОЛ ПЕРЕРАСЧЁТА СУБСИДИИ НА ОПЛАТУ ЖКУ И КОММУНАЛЬНЫХ УСЛУГ' || _br
					 || CASE _c_recalculation_reason_alias 
							WHEN 'ending_payment_period' THEN 'В СВЯЗИ С ИЗМЕНЕНИЕМ СУММЫ НАЧИСЛЕНИЙ ЗА ЖКУ' || _br
							ELSE ''
						END;
	ELSE
		_c_header := 'ПРОТОКОЛ РАСЧЁТА СУБСИДИИ НА ОПЛАТУ ЖИЛОГО ПОМЕЩЕНИЯ И КОММУНАЛЬНЫХ УСЛУГ' || _br;
	END IF;

	_c_header := _c_header || public.get_russian_date(_date_recalculation) || _br
						   || '№ личного дела: ' || COALESCE(_с_case_number, '') || _br
						   || 'ФИО заявителя: ' || COALESCE(_с_declarant, '') || _br
						   || 'Дата обращения: ' || COALESCE(public.get_russian_date(_date_calculation), '')
						   || _с_divider
						   || 'Адрес: ' || COALESCE(_с_address, '') || _br
						   || 'Балансодержатель: ' || COALESCE(_c_balance_holder, '') || _br
						   || 'Жилищный фонд: ' || COALESCE(_с_housing_stock_type, '') || _br
						   || 'Вид дома: ' || COALESCE(_c_ownership_type, '') || _br
						   || 'Взносы на кап. рем.: ' || COALESCE(_c_capital_repair, '') 
						   || _с_divider;
	
	
	_protocol := COALESCE(_c_header, '');
	-- обновляем данные по расчёту
	UPDATE subsidy.cd_calculations
	SET c_result = _protocol
	WHERE id = _calc;
	
END
$function$
;