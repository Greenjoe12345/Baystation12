/obj/machinery/optable
	name = "Operating Table"
	desc = "Used for advanced medical procedures."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "table2-idle"
	density = TRUE
	anchored = TRUE
	throwpass = 1
	idle_power_usage = 1
	active_power_usage = 5
	construct_state = /decl/machine_construction/default/panel_closed
	uncreated_component_parts = null
	stat_immune = 0

	machine_name = "operating table"
	machine_desc = "A sterile and well-lit surface to conduct surgery. Operating tables are the only completely safe surfaces to perform operations. Comes with built-in neural suppressors to anesthetize a patient laying on top of it."

	var/suppressing = FALSE
	var/mob/living/carbon/human/victim = null
	var/strapped = 0.0
	var/obj/machinery/computer/operating/computer = null
	var/obj/machinery/vitals_monitor/connected_monitor = null

/obj/machinery/optable/Initialize()
	. = ..()
	for(dir in list(NORTH,EAST,SOUTH,WEST))
		computer = locate(/obj/machinery/computer/operating, get_step(src, dir))
		if (computer)
			computer.table = src
			break

/obj/machinery/optable/Destroy()
	victim = null
	if(connected_monitor)
		connected_monitor.update_victim()
		connected_monitor.update_optable()
	. = ..()

/obj/machinery/optable/examine(mob/user)
	. = ..()
	to_chat(user, "<span class='notice'>The neural suppressors are switched [suppressing ? "on" : "off"].</span>")

/obj/machinery/optable/ex_act(severity)

	switch(severity)
		if(EX_ACT_DEVASTATING)
			//SN src = null
			qdel(src)
			return
		if(EX_ACT_HEAVY)
			if (prob(50))
				//SN src = null
				qdel(src)
				return
		if(EX_ACT_LIGHT)
			if (prob(25))
				src.set_density(0)

/obj/machinery/optable/attackby(obj/item/O, mob/user)
	if (istype(O, /obj/item/grab))
		var/obj/item/grab/G = O
		if(iscarbon(G.affecting) && check_table(G.affecting))
			take_victim(G.affecting,usr)
			qdel(O)
			return
	return ..()

/obj/machinery/optable/state_transition(decl/machine_construction/default/new_state)
	. = ..()
	if(istype(new_state))
		updateUsrDialog()

/obj/machinery/optable/physical_attack_hand(mob/user)
	if(MUTATION_HULK in user.mutations)
		visible_message("<span class='danger'>\The [usr] destroys \the [src]!</span>")
		src.set_density(0)
		qdel(src)
		return TRUE

	if(!victim)
		to_chat(user, "<span class='warning'>There is nobody on \the [src]. It would be pointless to turn the suppressor on.</span>")
		return TRUE

	if(user != victim && !suppressing) // Skip checks if you're doing it to yourself or turning it off, this is an anti-griefing mechanic more than anything.
		user.visible_message("<span class='warning'>\The [user] begins switching on \the [src]'s neural suppressor.</span>")
		if(!do_after(user, 3 SECONDS, src, DO_PUBLIC_UNIQUE) || !user || !src || user.incapacitated() || !user.Adjacent(src))
			return TRUE
		if(!victim)
			to_chat(user, "<span class='warning'>There is nobody on \the [src]. It would be pointless to turn the suppressor on.</span>")
			return TRUE

	suppressing = !suppressing
	user.visible_message("<span class='notice'>\The [user] switches [suppressing ? "on" : "off"] \the [src]'s neural suppressor.</span>")
	if (victim.stat == UNCONSCIOUS)
		to_chat(victim, SPAN_NOTICE(SPAN_BOLD("... [pick("good feeling", "white light", "pain fades away", "safe now")] ...")))
	return TRUE

/obj/machinery/optable/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(air_group || (height==0)) return 1

	if(istype(mover) && mover.checkpass(PASS_FLAG_TABLE))
		return 1
	else
		return 0


/obj/machinery/optable/MouseDrop_T(mob/target, mob/user)
	if (target.loc != loc)
		step(target, get_dir(target, loc))
	..()

/obj/machinery/optable/proc/check_victim()
	if(!victim || !victim.lying || victim.loc != loc)
		suppressing = FALSE
		victim = null
		if(connected_monitor)
			connected_monitor.update_victim()
		if(locate(/mob/living/carbon/human) in loc)
			for(var/mob/living/carbon/human/H in loc)
				if(H.lying)
					victim = H
					if(connected_monitor)
						connected_monitor.update_victim(H)
					break
	icon_state = (victim && victim.pulse()) ? "table2-active" : "table2-idle"
	if(victim)
		if(suppressing && victim.sleeping < 3)
			victim.Sleeping(3 - victim.sleeping)
		return 1
	return 0

/obj/machinery/optable/Process()
	check_victim()

/obj/machinery/optable/proc/take_victim(mob/living/carbon/C, mob/living/carbon/user as mob)
	if (C == user)
		user.visible_message("[user] climbs on \the [src].","You climb on \the [src].")
	else
		visible_message("<span class='notice'>\The [C] has been laid on \the [src] by [user].</span>")
	if (C.client)
		C.client.perspective = EYE_PERSPECTIVE
		C.client.eye = src
	C.Weaken(5)
	C.dropInto(loc)
	src.add_fingerprint(user)
	if(ishuman(C))
		var/mob/living/carbon/human/H = C
		src.victim = H
		if(connected_monitor)
			connected_monitor.update_victim(H)
		icon_state = H.pulse() ? "table2-active" : "table2-idle"
	else
		icon_state = "table2-idle"

/obj/machinery/optable/MouseDrop_T(mob/target, mob/user)
	var/mob/living/M = user
	if(user.stat || user.restrained() || !iscarbon(target) || !check_table(target))
		return
	if(istype(M))
		take_victim(target,user)
	else
		return ..()

/obj/machinery/optable/climb_on()
	if(usr.stat || !ishuman(usr) || usr.restrained() || !check_table(usr))
		return

	take_victim(usr,usr)

/obj/machinery/optable/proc/check_table(mob/living/carbon/patient as mob)
	check_victim()
	if(src.victim && get_turf(victim) == get_turf(src) && victim.lying)
		to_chat(usr, "<span class='warning'>\The [src] is already occupied!</span>")
		return 0
	if(patient.buckled)
		to_chat(usr, "<span class='notice'>Unbuckle \the [patient] first!</span>")
		return 0
	return 1
