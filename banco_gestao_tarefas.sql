/*
FUNCOES

CREATE FUNCTION funcao ([parâmetro [tipo, numeric, int, etc..]], ...)
RETURNS [tipo(numeric, int, etc..)] AS $$
BEGIN
	RETURN;
END;
$$ LANGUAGE plpgsql;

CHAMAR A FUNCAO
SELECT funcao 

TRIGGERS
CREATE FUNCTION trig_funca
*/


--TABELAS

create table colaboradores (
	id serial primary key,
	nome varchar(200) not null,
	email varchar(200) unique not null,
	cpf_criptografado bytea not null,
	senha_hash varchar(64) not null,
	--revisar sobre hash depois
	ativo boolean default true,
	data_cadastro timestamp default current_timestamp
);

create table categorias (
	id serial primary key,
	nome varchar(100) unique not null
);

create table tarefas (
	id serial primary key,
	titulo varchar(100),
	categoria_id int references categorias(id),
	colaborador_id int references colaboradores(id),
	descricao text,
	data_entrega date not null,
	--'date' armazena como ano/mes/dia
	status varchar(100) default 'Pendente' check  (status in ('Pendente', 'Feita', 'Fazendo', 'Cancelada')),
	data_criacao timestamp default current_timestamp
);

create table historico_tarefas (
	id serial primary key,
	tarefa_id int references tarefas(id) on delete cascade,
	observacao varchar(200) not null,
	data_alteracao timestamp default current_timestamp
);

--INSERTS

insert into colaboradores (nome, email, cpf_criptografado, senha_hash, ativo) values 
('Joao', 'joao@email.com', pgp_sym_encrypt('11111111100', 'senhalgpd'), encode(digest('senhajoao', 'sha256'), 'hex'), true),
('Joselina', 'joselina@email.com', pgp_sym_encrypt('22222222200', 'senhalgpd'), encode(digest('senhajoselina', 'sha256'), 'hex'), true),
('Julio', 'julio@email.com', pgp_sym_encrypt('33333333300', 'senhalgpd'), encode(digest('senhajulio', 'sha256'), 'hex'), true);

--criptografar (se quiser mostrar o texto em algum lugar): pgp_sym_encrypt([texto], [senha])
--criptografa (para ninguem ver): encode(digest('[texto]', 'sha256'), 'hex')

insert into categorias(nome) values
('Revisão'),
('Apresentação'),
('Reunião');

insert into tarefas(titulo, categoria_id, colaborador_id, descricao, data_entrega, status) values
('fazer isso', '1', '1', 'tem que fazer isso', current_date + interval '7 days', 'Pendente'),
('fazer aquilo', '2', '2', 'tem que fazer aquilo', current_date + interval '6 days', 'Pendente'),
('fazer outro', '3', '3', 'tem que fazer outro', current_date + interval '5 days', 'Cancelada');

--data daqui a x dias: current_date + interval 'x days'



--FUNCOES
create or replace function fn_buscar_colaboradores (busca varchar)
returns table (
	id int,
	nome_colaborador varchar,
	email_colaborador varchar,
	cpf_descriptografado text,
	colaborador_ativo boolean
) AS $$
begin
	return query
	select 
		c.id,
		c.nome,
		c.email,
		pgp_sym_decrypt(c.cpf_criptografado, 'senhalgpd')::TEXT,
		c.ativo
	from colaboradores c
	where LOWER(nome) LIKE LOWER('%' || busca || '%')
		or LOWER(email) LIKE LOWER('%' || busca || '%');
end;
$$ LANGUAGE plpgsql;

--TRIGGERS
CREATE OR REPLACE FUNCTION fn_trg_validar_tarefa()
returns trigger AS $$
declare
	v_ativo boolean;
begin
	select ativo into v_ativo from colaboradores where id = NEW.colaborador_id;

	IF v_ativo is not true then
		raise exception 'Colaborador não pode ser inativo ou inexistente';
	end if;
	
	RETURN NEW;
end;
$$ language plpgsql;

CREATE TRIGGER trg_validar_tarefa
BEFORE INSERT on tarefas
for each row
execute function fn_trg_validar_tarefa();


create or replace function fn_trg_logar_tarefa ()
returns trigger as $$
declare
	c_nome colaboradores.nome%type;
begin
	select nome into c_nome from colaboradores where id = NEW.colaborador_id;

	insert into historico_tarefas(tarefa_id, observacao) values
	(NEW.id, 'tarefa criada e com status: ' || NEW.status || ' e atribuída ao colaborador: ' || COALESCE(c_nome, 'colaborador sem nome'));

return new;
end;
$$ language plpgsql;

create trigger trg_logar_tarefa
after insert on tarefas
for each row 
execute function fn_trg_logar_tarefa();

--VIEW
CREATE OR REPLACE VIEW vw_cronogama_prazos AS
SELECT
	t.titulo, --nome da tarefa
	cg.nome, --categoria
	t.data_entrega,
	(t.data_entrega - current_date) as dias_restantes, --dias até a data de entrega
	t.status,
	c.nome as colaborador_responsavel
from tarefas t
join colaboradores c on t.colaborador_id = c.id
join categorias cg on t.categoria_id = cg.id
ORDER BY t.data_entrega ASC;


/*
	titulo varchar(100),
	categoria_id int references categorias(id),
	colaborador_id int references colaboradores(id),
	descricao text,
	data_entrega date not null,
	--'date' armazena como ano/mes/dia
	status varchar(100) default 'Pendente' check  (status in ('Pendente', 'Feita', 'Fazendo', 'Cancelada')),
	data_criacao timestamp default current_timestamp
*/

--FUNCOES
create or replace function fn_autenticar_usuario (
	login_email varchar,
	login_senha varchar
)
returns table (
	autenticado boolean,
	colaborador_id int,
	nome varchar,
	mensagem varchar
) as $$
declare
	--coloquei para teste
	msg_erro_dados varchar := 'usuario/senha invalidos';
	msg_erro_ativo varchar := 'colaborador inativo';
	msg_sucesso varchar := 'Autenticado com sucesso';
	
	v_hash varchar(64);
	v_id int;
	v_nome varchar(100);
	v_ativo boolean;
begin
	--converter senha colocada para hash
	v_hash := encode(digest(login_senha, 'sha256'), 'hex');

	select c.id, c.nome, c.ativo into v_id, v_nome, v_ativo 
	from colaboradores c 
	where v_hash = c.senha_hash and login_email = c.email;
	--Aqui, ele vai procurar pelo id, nome e status dos colaboradores e copiar para dentro das variaveis v_id, v_nome e v_ativo, cujo email e hash de senha batam com os parametros apresentados. Se nenhum colaborador tiver o email E senha correspondentes, v_id sera NULL por padrao.
	
	--verificar se v_id = NULL (senha/email nao bate)
	--verficar se v_ativo = false (colaborador inativo, logo nao deve ser possivel entrar)
	if v_id is NULL then
		return query select 
			false, 
			null::int, 
			null::varchar, 
			msg_erro_dados;
	elsif v_ativo is not true then
		return query select 
			false, 
			null::int, 
			null::varchar, 
			msg_erro_ativo;
	else 
		return query select 
			true, 
			v_id, 
			v_nome, 
			msg_sucesso;
		end if;
	end;
$$ language plpgsql;



--SELECT
select fn_autenticar_usuario ('julio@email.com', 'senhajulio');

select fn_autenticar_usuario ('joselina@email.com', 'senhaerrada');

select * from fn_buscar_colaboradores('Joao');