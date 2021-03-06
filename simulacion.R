library(tidyverse)
library(dplyr)
library(tidygraph)

#CONSTANTES
pop_tot <- sum(cdmx$poblacion, na.rm = TRUE)
n_dis <- 24
wd <- 0.4
wc <- 2.5
wp <- 30000

#FUNCIONES
pop_score_duke <- function(V){
  pop_ideal <- round(pop_tot / n_dis)
  
  score <- V %>%
    group_by(distrito) %>%
    summarise(pop_dist = sum(poblacion)) %>%
    transmute(prop_dist = (pop_dist / pop_ideal - 1)^2) %>%
    summarise(score = sum(prop_dist)) %>%
    as.numeric()
  
  return(score)
}

is_conflicting <- function(V, u, v){
  flag <- V %>%
    filter(seccion %in% c(u,v)) %>%
    pull(distrito) %>%
    unique() %>%
    length()
  
  return(flag > 1)
  
}

detect_conflicting <- function(E, V){
  n <- nrow(E)
  indices <- rep(FALSE, n)
  
  for(i in 1:n){
    u <- E[i, 'from']
    v <- E[i, 'to']
    indices[i] <- is_conflicting(V, u, v)
  }
  
  return(indices)
}


detect_conflicting_lim_scope <- function(E, V, u, v){
  n <- nrow(E)
  indices <- rep(FALSE, n)
  
  for(i in 1:n){
    x <- E[i, 'from']
    y <- E[i, 'to']
    if(x %in% c(u,v) | y %in% c(u,v)){
      indices[i] <- is_conflicting(V, x, y)
    }else{
      indices[i] <- E[i, 'conflicting']
    }
  }
  return(indices)
}

boundaries <- function(E, V){
  
  n <- nrow(E)
  bdy <- rep(0, n_dis)
  
  for(i in 1:n){
    u <- E[i, 'from']
    v <- E[i, 'to']
    if(E[i, 'conflicting']){
      d1 <- cdmx[which(cdmx$seccion == u), 'distrito']
      d2 <- cdmx[which(cdmx$seccion == v), 'distrito']
      if(d1 != 0){
        bdy[d1] <- bdy[d1] + E[i, 'weight']
      }
      if(d2 != 0){
        bdy[d2] <- bdy[d2] + E[i, 'weight']
      }
    }
  }
  
  return(bdy)
  
}

area <- function(V){
  return(
    V %>%
      group_by(distrito) %>%
      summarise(dist_area = sum(area))
  )
}

iso_score_duke <- function(E, V){
  areas <- area(V) %>% 
    pull(dist_area) %>% 
    '['(-1)
  bdys <- boundaries(E)
  
  score <- bdys^2/areas
  return(score)
}

county_score_duke <- function(V){
  distritos_por_delegacion <- V %>%
    group_by(delegacion) %>%
    summarise(num_distritos = distrito %>% unique() %>% length()) %>%
    filter(num_distritos >= 2) %>%
    filter(!is.na(delegacion))
  
  w2 <- V %>%
    filter(!is.na(distrito)) %>%
    group_by(distrito, delegacion) %>%
    count() %>%
    arrange(delegacion, n) %>%
    group_by(delegacion) %>%
    summarise(sec_largest = n %>% sort(na.last = TRUE, decreasing = TRUE) %>% '['(2),
              n_tot = sum(n)) %>%
    filter(!is.na(sec_largest)) %>%
    filter(!is.na(delegacion)) %>%
    mutate(proporcion = sec_largest / n_tot) %>%
    summarise(score = proporcion %>% sqrt() %>% sum())
  
  w3 <- V %>%
    filter(!is.na(distrito)) %>%
    group_by(distrito, delegacion) %>%
    count() %>%
    group_by(delegacion) %>%
    summarise(all_but_two = n %>% sort(na.last = NA, decreasing = TRUE) %>% '['(-c(1,2)) %>% sum(),
              n_tot = sum(n)) %>%
    arrange(delegacion) %>%
    mutate(proporcion = all_but_two / n_tot) %>%
    summarise(score = proporcion %>% sqrt() %>% sum())
  
  
  cuantos_2 <- sum(distritos_por_delegacion$num_distritos == 2)
  cuantos_mas <- sum(distritos_por_delegacion$num_distritos > 2)
  
  return(w2*cuantos_2 + w3*100*cuantos_mas)
  
}



revisar_conexidad <- function(E, V_temp){
  temp_graph <- graph_from_data_frame(
    d = E,
    directed = FALSE,
    vertices = V_temp
  )
  for(i in 1:n_dis){
    indices <- which(V_temp$distrito == i)
    n_comps <- temp_graph %>%
      induced_subgraph(indices) %>%
      count_components()
    if(n_comps != 1 ){
      return(FALSE)
    }
  }
  return(TRUE)
}


score <- function(E, V, wd, wp, wi){
  return(wd*county_score_duke(V) + wp*pop_score_duke(V) + wi*iso_score_duke(E,V))
}

una_iteracion <- function(G, E, V, beta, wd, wp, wi){
  l <- generar_nuevo_estado(E, V)
  V_temp <- l[[1]]
  u <- l[[2]]
  v <- l[[3]]
  
  temp_graph <- graph_from_data_frame(
    d = E,
    directed = FALSE,
    vertices = V_temp
  )
  
  if(revisar_conexidad(E, V_temp)){
    new_conflicting <- detect_conflicting_lim_scope(E, V_temp, u, v)
    rho <- sum(E$conflicting) %>%
      '/'(sum(new_conflicting)) %>%
      '*'(exp(-beta*(score(E, V_temp, wd, wp, wi)-score(E, V, wd, wp, wi))))
    if(runif(1) < rho){
      E_temp <- E
      E_temp$conflicting <- new_conflicting
      return(list(temp_graph, E_temp, V_temp))
    }
  }
  return(list(G, E, V))
}

generar_nuevo_estado <- function(E, V){
  temp <- V
  conflicting <- which(E$conflicting & E$from!=0)
  
  ind_samp <- sample(conflicting, 1)
  u <- E[ind_samp,'from'] 
  v <- E[ind_samp, 'to']
  ind_u <- which(V$seccion == u)
  ind_v <- which(V$seccion == v)
  
  if(rbinom(1,1,1/2)){
    temp[ind_u, 'distrito'] <- V[ind_v, 'distrito']
  }else{
    temp[ind_v, 'distrito'] <- V[ind_u, 'distrito']
  }
  return(list(temp, u, v))
}


take_one_sample <- function(G, E, V, wd, wp, wi){
  l <- list(G, E, V)
  
  print('primer for')
  for(i in 1:40000){
    l <- una_iteracion(l[[1]], l[[2]], l[[3]], 0, wd, wp, wi)
  }
  
  print('segundo for')
  lin_beta <- seq(from = 0, to = 1, length.out = 60000)
  #for(i in 1:60000){
  for(i in 1:60000){
    l <- una_iteracion(l[[1]], l[[2]], l[[3]], lin_beta[i], wd, wp, wi)
  }
  
  print('tercer for')
  for(i in 1:20000){
    l <-  una_iteracion(l[[1]], l[[2]], l[[3]], 1, wd, wp, wi)
  }
  
  return(l[[3]]$distrito)
  print('muestra tomada')
}






